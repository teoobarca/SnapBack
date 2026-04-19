package com.snapback.mobile.ui.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

object SnapBackColors {
    val Orange = Color(0xFFE07D4F)
    val OrangeDark = Color(0xFFB8633F)
    val OrangeLight = Color(0xFFF5E6DD)
    val StatusGreen = Color(0xFF2E7D32)
    val OverlayBg = Color(0xFF1A1A1A)
    val MutedGray = Color(0xFF9E9E9E)
}

private val LightColorScheme = lightColorScheme(
    primary = Color(0xFFE07D4F),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFF5E6DD),
    onPrimaryContainer = Color(0xFFB8633F),
    secondary = Color(0xFF6B6B6B),
    onSecondary = Color.White,
    background = Color(0xFFFAFAFA),
    onBackground = Color(0xFF1C1B1F),
    surface = Color.White,
    onSurface = Color(0xFF1C1B1F),
    surfaceVariant = Color(0xFFF5F5F5),
    onSurfaceVariant = Color(0xFF6B6B6B),
    outline = Color(0xFFE0E0E0),
    error = Color(0xFFBA1A1A),
    onError = Color.White,
)

private val AppTypography = Typography(
    headlineMedium = Typography().headlineMedium.copy(fontWeight = FontWeight.SemiBold),
    titleMedium = Typography().titleMedium.copy(fontWeight = FontWeight.SemiBold),
)

private val AppShapes = Shapes(
    small = RoundedCornerShape(8.dp),
    medium = RoundedCornerShape(12.dp),
)

@Composable
fun SnapBackTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = LightColorScheme,
        typography = AppTypography,
        shapes = AppShapes,
        content = content,
    )
}
