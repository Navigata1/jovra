package com.islanddevcrew.jovra.designsystem.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val Forest = Color(0xFF092A25)
private val ForestPanel = Color(0xFF123C33)
private val Ivory = Color(0xFFF4F1E8)
private val Charcoal = Color(0xFF182F29)
private val Chartreuse = Color(0xFFD7F56A)
private val LightSurface = Color(0xFFFBFAF6)

private val LightColors = lightColorScheme(
    primary = Forest,
    onPrimary = Ivory,
    secondaryContainer = Forest,
    onSecondaryContainer = Chartreuse,
    background = Ivory,
    onBackground = Charcoal,
    surface = LightSurface,
    onSurface = Charcoal,
    onSurfaceVariant = Color(0xFF4D5853),
    surfaceContainer = LightSurface,
)

private val DarkColors = darkColorScheme(
    primary = Chartreuse,
    onPrimary = Forest,
    secondaryContainer = Chartreuse,
    onSecondaryContainer = Forest,
    background = Forest,
    onBackground = Ivory,
    surface = ForestPanel,
    onSurface = Ivory,
    onSurfaceVariant = Color(0xFFB4C2BB),
    surfaceContainer = Color(0xFF0D312B),
)

@Composable
fun JovraShellTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = if (isSystemInDarkTheme()) DarkColors else LightColors, content = content)
}
