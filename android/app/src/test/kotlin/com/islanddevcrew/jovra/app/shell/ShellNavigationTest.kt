package com.islanddevcrew.jovra.app.shell

import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.performClick
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ShellNavigationTest {
    @get:Rule
    val compose = createAndroidComposeRule<MainActivity>()

    @Test
    @Config(qualifiers = "w360dp-h800dp")
    fun compactLaunchShowsFiveLabelledDestinationsInABottomBar() {
        assertDestinationsAndSelectSessions()
        val home = destination("Home").getUnclippedBoundsInRoot()
        val profile = destination("Profile").getUnclippedBoundsInRoot()
        val heading = compose.onNode(hasText("Sessions") and !hasClickAction()).getUnclippedBoundsInRoot()
        assertEquals(home.top, profile.top)
        assertTrue(home.left < profile.left)
        assertTrue(heading.bottom < home.top)
    }

    @Test
    @Config(qualifiers = "w840dp-h900dp")
    fun expandedLaunchShowsTheSameDestinationsInARail() {
        assertDestinationsAndSelectSessions()
        val home = destination("Home").getUnclippedBoundsInRoot()
        val profile = destination("Profile").getUnclippedBoundsInRoot()
        val heading = compose.onNode(hasText("Sessions") and !hasClickAction()).getUnclippedBoundsInRoot()
        assertEquals(home.left, profile.left)
        assertTrue(home.top < profile.top)
        assertTrue(home.right < heading.left)
    }

    private fun assertDestinationsAndSelectSessions() {
        val names = listOf("Home", "Sessions", "Record", "Insights", "Profile")
        compose.onAllNodes(hasClickAction()).assertCountEquals(names.size)
        names.forEach { destination(it).assertIsDisplayed() }
        destination("Home").assertIsSelected()
        destination("Sessions").performClick().assertIsSelected()
        compose.onNode(hasText("Sessions") and !hasClickAction()).assertIsDisplayed()
    }

    private fun destination(name: String) = compose.onNode(hasText(name) and hasClickAction())
}
