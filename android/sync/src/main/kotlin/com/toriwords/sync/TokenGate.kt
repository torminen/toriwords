package com.toriwords.sync

interface TokenGate { suspend fun ensureAuthorized(foreground: Boolean): AuthResult }
sealed interface AuthResult { data object Ok : AuthResult; data object NeedsResolution : AuthResult }
