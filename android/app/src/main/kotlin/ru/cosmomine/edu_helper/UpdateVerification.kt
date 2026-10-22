package ru.cosmomine.edu_helper

import java.io.File
import java.security.MessageDigest

internal object UpdateVerification {
    fun checkFile(file: File, size: Long, hash: String) {
        require(file.isFile && file.length() == size)
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(65536)
            while (true) { val n = input.read(buffer); if (n == -1) break; digest.update(buffer, 0, n) }
        }
        require(digest.digest().joinToString("") { "%02x".format(it) } == hash)
    }

    fun checkIdentity(installedPackage: String, candidatePackage: String,
                      installedBuild: Long, candidateBuild: Long, expectedBuild: Long,
                      installedSignatures: Set<String>, candidateSignatures: Set<String>) {
        require(candidatePackage == installedPackage)
        require(candidateBuild == expectedBuild && candidateBuild > installedBuild)
        require(installedSignatures.isNotEmpty() && candidateSignatures == installedSignatures)
    }
}
