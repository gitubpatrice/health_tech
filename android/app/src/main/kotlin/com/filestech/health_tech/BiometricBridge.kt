package com.filestech.health_tech

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/// Bridge backing `lib/data/vault/biometric_channel.dart`.
///
/// Exposes four operations on a Keystore-bound AES-GCM key whose private
/// material never leaves the secure hardware:
///   - `isAvailable`  : strongClass3 biometrics enrolled & usable.
///   - `wrap`         : encrypt a plaintext VEK with a fresh Keystore key.
///                      Encryption does NOT require user authentication —
///                      only decryption does — so we can run this silently
///                      right after the user opts in to biometric unlock.
///   - `unwrap`       : show BiometricPrompt; on success, the bound Cipher
///                      decrypts the previously wrapped VEK.
///   - `delete`       : drop the Keystore entry (called when the user
///                      disables biometric or after too many failures).
///
/// The Cipher has `setUserAuthenticationRequired(true)` and, on API 24+,
/// `setInvalidatedByBiometricEnrollment(true)` — adding a new fingerprint
/// invalidates the key, forcing the user to re-enable from passphrase.
class BiometricBridge(
    private val activity: FragmentActivity,
    messenger: io.flutter.plugin.common.BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL = "com.filestech.health_tech/biometric"
        private const val KEYSTORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "health_tech_biometric_v1"
        private const val GCM_TAG_BITS = 128
    }

    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(isStrongBiometricAvailable())
            "wrap" -> handleWrap(call, result)
            "unwrap" -> handleUnwrap(call, result)
            "delete" -> {
                deleteKey()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun isStrongBiometricAvailable(): Boolean {
        val mgr = BiometricManager.from(activity)
        val authenticators = BiometricManager.Authenticators.BIOMETRIC_STRONG
        return mgr.canAuthenticate(authenticators) ==
                BiometricManager.BIOMETRIC_SUCCESS
    }

    private fun handleWrap(call: MethodCall, result: MethodChannel.Result) {
        val plaintextB64 = call.argument<String>("plaintext")
            ?: return result.error("bad_args", "plaintext missing", null)
        val title = call.argument<String>("title") ?: "Authenticate"
        val subtitle = call.argument<String>("subtitle") ?: ""
        val negative = call.argument<String>("negativeButton") ?: "Cancel"

        // The Keystore key is generated with setUserAuthenticationRequired(true)
        // which means EVERY use — encrypt as well as decrypt — must go through
        // BiometricPrompt with a CryptoObject. We therefore prompt the user
        // once at enable-time, bind the cipher to the auth result, and only
        // then perform the encryption.
        val cipher: Cipher
        try {
            deleteKey()
            val key = generateKey()
            cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key)
        } catch (e: Exception) {
            // On ne renvoie PAS e.message : il peut contenir un alias
            // Keystore, un chemin natif ou une info de hardware (Samsung
            // Knox, Qualcomm StrongBox) qui finirait dans logcat. Code
            // générique côté Dart, log détaillé côté Kotlin gated debug.
            if (BuildConfig.DEBUG) android.util.Log.w("BiometricBridge", "wrap_init failed", e)
            return result.error("wrap_init_failed", "wrap init failed", null)
        }
        val iv = cipher.iv

        val executor = ContextCompat.getMainExecutor(activity)
        val prompt = BiometricPrompt(
            activity,
            executor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationError(
                    errorCode: Int,
                    errString: CharSequence,
                ) {
                    result.error("auth_error", "$errorCode: $errString", null)
                }

                override fun onAuthenticationSucceeded(
                    auth: BiometricPrompt.AuthenticationResult,
                ) {
                    try {
                        val bound = auth.cryptoObject?.cipher
                            ?: throw IllegalStateException("crypto object missing")
                        val plaintext = Base64.decode(plaintextB64, Base64.NO_WRAP)
                        val ciphertext = bound.doFinal(plaintext)
                        plaintext.fill(0)
                        result.success(
                            mapOf(
                                "iv" to Base64.encodeToString(iv, Base64.NO_WRAP),
                                "ciphertext" to Base64.encodeToString(
                                    ciphertext,
                                    Base64.NO_WRAP,
                                ),
                            ),
                        )
                    } catch (e: Exception) {
                        if (BuildConfig.DEBUG) android.util.Log.w("BiometricBridge", "wrap failed", e)
                        result.error("wrap_failed", "wrap failed", null)
                    }
                }
            },
        )

        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setSubtitle(subtitle)
            .setNegativeButtonText(negative)
            .setAllowedAuthenticators(
                BiometricManager.Authenticators.BIOMETRIC_STRONG,
            )
            .build()

        activity.runOnUiThread {
            prompt.authenticate(info, BiometricPrompt.CryptoObject(cipher))
        }
    }

    private fun handleUnwrap(call: MethodCall, result: MethodChannel.Result) {
        val ivB64 = call.argument<String>("iv")
            ?: return result.error("bad_args", "iv missing", null)
        val cipherB64 = call.argument<String>("ciphertext")
            ?: return result.error("bad_args", "ciphertext missing", null)
        val title = call.argument<String>("title") ?: "Authenticate"
        val subtitle = call.argument<String>("subtitle") ?: ""
        val negative = call.argument<String>("negativeButton") ?: "Cancel"

        val key = try {
            loadKey()
        } catch (e: Exception) {
            return result.error("no_key", "Biometric key not provisioned", null)
        }
        if (key == null) {
            return result.error("no_key", "Biometric key not provisioned", null)
        }

        val cipher: Cipher
        try {
            cipher = Cipher.getInstance("AES/GCM/NoPadding")
            val iv = Base64.decode(ivB64, Base64.NO_WRAP)
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_BITS, iv))
        } catch (e: KeyPermanentlyInvalidatedException) {
            // L'utilisateur a enrolled une nouvelle empreinte → la clé
            // Keystore est invalidée par `setInvalidatedByBiometricEnrollment`.
            // On la supprime pour que le prochain `enableBiometric` reparte
            // d'une clé saine ; le caller Dart wipe les blobs IV/CT au
            // niveau du vault.
            deleteKey()
            return result.error(
                "key_invalidated",
                "biometric enrollment changed — re-enable from passphrase",
                null,
            )
        } catch (e: Exception) {
            if (BuildConfig.DEBUG) android.util.Log.w("BiometricBridge", "cipher_init failed", e)
            return result.error("cipher_init", "cipher init failed", null)
        }

        val executor = ContextCompat.getMainExecutor(activity)
        val prompt = BiometricPrompt(
            activity,
            executor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    result.error("auth_error", "$errorCode: $errString", null)
                }

                override fun onAuthenticationFailed() {
                    // Stays on the prompt so the user can retry; we report
                    // back only on hard error or explicit cancel.
                }

                override fun onAuthenticationSucceeded(
                    auth: BiometricPrompt.AuthenticationResult,
                ) {
                    try {
                        val bound = auth.cryptoObject?.cipher
                            ?: throw IllegalStateException("crypto object missing")
                        val ciphertext = Base64.decode(cipherB64, Base64.NO_WRAP)
                        val plaintext = bound.doFinal(ciphertext)
                        val outB64 =
                            Base64.encodeToString(plaintext, Base64.NO_WRAP)
                        plaintext.fill(0)
                        result.success(outB64)
                    } catch (e: Exception) {
                        if (BuildConfig.DEBUG) android.util.Log.w("BiometricBridge", "decrypt failed", e)
                        result.error("decrypt_failed", "decrypt failed", null)
                    }
                }
            },
        )

        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setSubtitle(subtitle)
            .setNegativeButtonText(negative)
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
            .build()

        activity.runOnUiThread {
            prompt.authenticate(info, BiometricPrompt.CryptoObject(cipher))
        }
    }

    private fun generateKey(): SecretKey {
        val builder = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            builder.setInvalidatedByBiometricEnrollment(true)
        }
        val gen = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            KEYSTORE,
        )
        gen.init(builder.build())
        return gen.generateKey()
    }

    private fun loadKey(): SecretKey? {
        val ks = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        return ks.getKey(KEY_ALIAS, null) as? SecretKey
    }

    private fun deleteKey() {
        try {
            val ks = KeyStore.getInstance(KEYSTORE).apply { load(null) }
            if (ks.containsAlias(KEY_ALIAS)) ks.deleteEntry(KEY_ALIAS)
        } catch (_: Exception) {
            // Best-effort: a leftover entry will be overwritten on the
            // next wrap() call.
        }
    }
}
