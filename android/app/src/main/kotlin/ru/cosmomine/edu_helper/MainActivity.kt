package ru.cosmomine.edu_helper

import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.HttpURLConnection
import java.net.URI
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private lateinit var channel: MethodChannel
    private val worker = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private val cancelled = AtomicBoolean(false)
    @Volatile private var connection: HttpURLConnection? = null
    private var working = false
    private var awaitingPermission = false
    private var verified: Release? = null
    private val directory get() = File(cacheDir, "updates")
    private val apk get() = File(directory, "update.apk")
    private data class Release(val url: String, val hash: String, val size: Long, val build: Long)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ru.cosmomine.edu_helper/updates")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "info" -> {
                    val installed = ownPackage()
                    result.success(mapOf("version" to installed.versionName, "build_number" to version(installed)))
                }
                "download" -> {
                    if (working) { result.error("busy", "Скачивание уже идёт", null); return@setMethodCallHandler }
                    try {
                        val release = Release(call.argument<String>("apk_url") ?: "",
                            call.argument<String>("sha256") ?: "",
                            call.argument<Number>("size")?.toLong() ?: 0,
                            call.argument<Number>("build_number")?.toLong() ?: 0)
                        val uri = URI(release.url)
                        require(uri.scheme == "https" && uri.host == "eduhelper.cosmomine.ru" &&
                            uri.port == -1 && uri.rawUserInfo == null && uri.rawQuery == null && uri.rawFragment == null &&
                            Regex("/downloads/eduhelper-[0-9]+\\.[0-9]+\\.[0-9]+\\.apk").matches(uri.path))
                        require(Regex("[a-f0-9]{64}").matches(release.hash) && release.size in 1..300_000_000 &&
                            release.build > version(ownPackage()))
                        working = true; cancelled.set(false); verified = null
                        worker.execute { download(release, result) }
                    } catch (_: Exception) { result.error("manifest", "Некорректные данные обновления", null) }
                }
                "cancel" -> { cancelled.set(true); connection?.disconnect(); result.success(null) }
                "install" -> {
                    if (working) { result.error("busy", "Дождитесь окончания скачивания", null); return@setMethodCallHandler }
                    val release = verified
                    if (release == null) { result.error("missing", "Скачайте обновление ещё раз", null); return@setMethodCallHandler }
                    working = true
                    worker.execute {
                        try {
                            verifyApk(release)
                            handler.post {
                                working = false
                                try { result.success(openInstaller()) }
                                catch (_: Exception) { result.error("installer", "Не удалось открыть установку обновления", null) }
                            }
                        } catch (_: Exception) {
                            apk.delete(); verified = null
                            handler.post { working = false; result.error("invalid", "Файл обновления не прошёл проверку. Скачайте его заново", null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun download(release: Release, result: MethodChannel.Result) {
        directory.mkdirs()
        val partial = File(directory, "update.part")
        try {
            partial.delete(); apk.delete()
            val request = URI(release.url).toURL().openConnection() as HttpURLConnection
            connection = request
            request.connectTimeout = 20_000; request.readTimeout = 30_000
            request.instanceFollowRedirects = false
            request.setRequestProperty("Accept-Encoding", "identity")
            require(request.responseCode == 200)
            val length = request.contentLengthLong
            require(length == -1L || length == release.size)
            var received = 0L
            var lastEvent = 0L
            val digest = MessageDigest.getInstance("SHA-256")
            request.inputStream.use { input ->
                partial.outputStream().use { output ->
                    val buffer = ByteArray(65536)
                    while (true) {
                        check(!cancelled.get())
                        val n = input.read(buffer)
                        if (n == -1) break
                        received += n
                        require(received <= release.size)
                        output.write(buffer, 0, n); digest.update(buffer, 0, n)
                        if (System.currentTimeMillis() - lastEvent >= 200) {
                            lastEvent = System.currentTimeMillis()
                            val progress = received
                            handler.post { channel.invokeMethod("progress", mapOf("received" to progress, "total" to release.size)) }
                        }
                    }
                }
            }
            check(!cancelled.get())
            require(received == release.size && hex(digest.digest()) == release.hash)
            check(partial.renameTo(apk))
            verifyApk(release)
            check(!cancelled.get())
            verified = release
            handler.post { working = false; result.success(null) }
        } catch (_: Exception) {
            partial.delete(); apk.delete(); verified = null
            val code = if (cancelled.get()) "cancelled" else "download"
            handler.post { working = false; result.error(code,
                if (code == "cancelled") "Скачивание отменено" else "Не удалось скачать или проверить обновление. Повторите попытку", null) }
        } finally { connection?.disconnect(); connection = null }
    }

    @Suppress("DEPRECATION")
    private fun ownPackage(): PackageInfo = packageManager.getPackageInfo(packageName, signatureFlags())
    private fun signatureFlags() = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
    @Suppress("DEPRECATION")
    private fun version(info: PackageInfo): Long = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
    @Suppress("DEPRECATION")
    private fun signatures(info: PackageInfo): Set<String> {
        val values = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        return values.orEmpty().map { hex(MessageDigest.getInstance("SHA-256").digest(it.toByteArray())) }.toSet()
    }
    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it) }
    @Suppress("DEPRECATION")
    private fun verifyApk(release: Release) {
        UpdateVerification.checkFile(apk, release.size, release.hash)
        val info = packageManager.getPackageArchiveInfo(apk.absolutePath, signatureFlags()) ?: error("Invalid APK")
        val installed = ownPackage()
        UpdateVerification.checkIdentity(packageName, info.packageName, version(installed), version(info),
            release.build, signatures(installed), signatures(info))
    }

    private fun openInstaller(): String {
        if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
            awaitingPermission = true
            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
            return "permission"
        }
        val uri = FileProvider.getUriForFile(this, "$packageName.updates", apk)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            clipData = ClipData.newRawUri("EduHelper update", uri)
        }
        startActivity(intent)
        return "installer"
    }

    override fun onResume() {
        super.onResume()
        if (awaitingPermission) {
            awaitingPermission = false
            if (Build.VERSION.SDK_INT < 26 || packageManager.canRequestPackageInstalls()) {
                try { openInstaller(); channel.invokeMethod("installerOpened", null) }
                catch (_: Exception) { channel.invokeMethod("installerError", null) }
            } else { channel.invokeMethod("permissionDenied", null) }
        }
    }

    override fun onDestroy() {
        cancelled.set(true); connection?.disconnect(); worker.shutdownNow()
        super.onDestroy()
    }
}
