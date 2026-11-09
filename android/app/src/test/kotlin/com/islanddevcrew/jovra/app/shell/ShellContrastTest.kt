package com.islanddevcrew.jovra.app.shell

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBarDefaults
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.NavigationRailItemDefaults
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteDefaults
import androidx.compose.material3.surfaceColorAtElevation
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.core.graphics.ColorUtils
import com.islanddevcrew.jovra.designsystem.theme.JovraShellTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ShellContrastTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    @Config(qualifiers = "notnight")
    fun lightShellColorRolesMeetContrastMinimums() = assertShellContrast(dark = false)

    @Test
    @Config(qualifiers = "night")
    fun darkShellColorRolesMeetContrastMinimums() = assertShellContrast(dark = true)

    private fun assertShellContrast(dark: Boolean) {
        var resolved: List<RolePair> = emptyList()
        var darkConfiguration: Boolean? = null
        compose.setContent {
            JovraShellTheme {
                val scheme = MaterialTheme.colorScheme
                val suite = NavigationSuiteDefaults.colors()
                val bar = NavigationBarItemDefaults.colors()
                val rail = NavigationRailItemDefaults.colors()
                val systemDark = isSystemInDarkTheme()
                val barContainer = if (suite.navigationBarContainerColor == scheme.surface) {
                    scheme.surfaceColorAtElevation(NavigationBarDefaults.Elevation)
                } else {
                    suite.navigationBarContainerColor
                }
                val pairs = listOf(RolePair("Shell text", scheme.onBackground, scheme.background, NORMAL_TEXT)) +
                    navigationPairs("Bar", barContainer.compositeOver(scheme.background), bar.selectedTextColor,
                        bar.unselectedTextColor, bar.selectedIconColor, bar.unselectedIconColor, bar.selectedIndicatorColor) +
                    navigationPairs("Rail", suite.navigationRailContainerColor.compositeOver(scheme.background),
                        rail.selectedTextColor, rail.unselectedTextColor, rail.selectedIconColor,
                        rail.unselectedIconColor, rail.selectedIndicatorColor)
                SideEffect {
                    darkConfiguration = systemDark
                    resolved = pairs
                }
            }
        }
        compose.runOnIdle {
            assertEquals("System theme qualifier", dark, darkConfiguration)
            assertEquals("Shell and both navigation role inventories", 11, resolved.size)
            val failures = resolved.mapNotNull { pair ->
                assertEquals("${pair.name} effective background must be opaque", 255, pair.background.toArgb() ushr 24)
                val ratio = ColorUtils.calculateContrast(pair.foreground.toArgb(), pair.background.toArgb())
                val detail = "${if (dark) "Dark" else "Light"} ${pair.name}: $ratio, minimum ${pair.minimum}"
                println(detail)
                detail.takeIf { ratio < pair.minimum }
            }
            assertTrue(failures.joinToString("\n"), failures.isEmpty())
        }
    }

    private fun navigationPairs(
        location: String,
        container: Color,
        selectedText: Color,
        unselectedText: Color,
        selectedIcon: Color,
        unselectedIcon: Color,
        indicator: Color,
    ): List<RolePair> = listOf(
        RolePair("$location selected label", selectedText, container, NORMAL_TEXT),
        RolePair("$location unselected label", unselectedText, container, NORMAL_TEXT),
        RolePair("$location selected icon", selectedIcon, indicator.compositeOver(container), NON_TEXT),
        RolePair("$location unselected icon", unselectedIcon, container, NON_TEXT),
        RolePair("$location selection indicator", indicator, container, NON_TEXT),
    )

    private data class RolePair(val name: String, val foreground: Color, val background: Color, val minimum: Double)

    // Match JovraCore ContrastRequirement.normalText and .nonText.
    private companion object {
        const val NORMAL_TEXT = 4.5
        const val NON_TEXT = 3.0
    }
}
