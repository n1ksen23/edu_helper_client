package ru.cosmomine.edu_helper

import org.junit.Test
import org.junit.Assert.assertThrows
import java.io.File

class UpdateVerificationTest {
    @Test fun rejectsCorruptAndTruncatedDownloads() {
        val file = File.createTempFile("update", ".apk")
        try {
            file.writeText("abc")
            val expected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
            UpdateVerification.checkFile(file, 3, expected)
            file.writeText("abd")
            assertThrows(IllegalArgumentException::class.java) { UpdateVerification.checkFile(file, 3, expected) }
            file.writeText("ab")
            assertThrows(IllegalArgumentException::class.java) { UpdateVerification.checkFile(file, 3, expected) }
        } finally { file.delete() }
    }
    @Test fun rejectsOtherApplicationsCertificatesAndDowngrades() {
        fun verify(name: String = "app", build: Long = 6, expected: Long = 6,
                   current: Set<String> = setOf("release-key"), candidate: Set<String> = setOf("release-key")) =
            UpdateVerification.checkIdentity("app", name, 5, build, expected, current, candidate)
        verify()
        assertThrows(IllegalArgumentException::class.java) { verify(name = "other") }
        assertThrows(IllegalArgumentException::class.java) { verify(build = 5, expected = 5) }
        assertThrows(IllegalArgumentException::class.java) { verify(build = 4, expected = 4) }
        assertThrows(IllegalArgumentException::class.java) { verify(expected = 7) }
        assertThrows(IllegalArgumentException::class.java) { verify(candidate = setOf("wrong-key")) }
        assertThrows(IllegalArgumentException::class.java) { verify(current = emptySet(), candidate = emptySet()) }
    }
}
