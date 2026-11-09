package com.islanddevcrew.jovra.app.shell

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.click
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasTextExactly
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ShellFontAndTouchTest {
    @get:Rule
    val compose = createEmptyComposeRule()

    @Test
    @Config(qualifiers = "w360dp-h800dp")
    fun compactBarKeepsLargeLabelsAndPointerTargets() = assertShellAtMaximumFont(widthDp = 360, compact = true)

    @Test
    @Config(qualifiers = "w840dp-h900dp")
    fun wideRailKeepsLargeLabelsAndPointerTargets() = assertShellAtMaximumFont(widthDp = 840, compact = false)

    private fun assertShellAtMaximumFont(widthDp: Int, compact: Boolean) {
        val previous = RuntimeEnvironment.getFontScale()
        try {
            RuntimeEnvironment.setFontScale(MAXIMUM_FONT_SCALE)
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                scenario.onActivity { activity ->
                    val configuration = activity.resources.configuration
                    assertEquals(widthDp, configuration.screenWidthDp)
                    assertEquals(MAXIMUM_FONT_SCALE, configuration.fontScale, 0f)
                }
                assertLargeNavigation(compact)
            }
        } finally {
            RuntimeEnvironment.setFontScale(previous)
        }
    }

    private fun assertLargeNavigation(compact: Boolean) {
        val names = listOf("Home", "Sessions", "Record", "Insights", "Profile")
        compose.onAllNodes(hasClickAction()).assertCountEquals(names.size)
        val viewport = compose.onRoot().fetchSemanticsNode().boundsInRoot
        val minimumPx = with(compose.density) { 48.dp.toPx() }
        val targets = names.map { name ->
            val destination = destination(name).assertIsDisplayed()
            val target = destination.fetchSemanticsNode().touchBoundsInRoot.intersect(viewport)
            val label = compose.onNode(
                hasTextExactly(name) and hasAnyAncestor(hasClickAction()) and textLayout,
                useUnmergedTree = true,
            )
            assertReadable(label, "navigation $name")
            println("${if (compact) "Compact" else "Wide"} $name visible touch bounds: $target, minimum ${minimumPx}px")
            assertTrue("$name effective touch bounds $target must be at least 48 × 48 dp",
                target.width >= minimumPx && target.height >= minimumPx)
            target
        }
        for ((index, first) in targets.withIndex()) {
            for (second in targets.drop(index + 1)) {
                assertTrue("Navigation touch bounds overlap: $first and $second", !first.overlaps(second))
                if (compact) assertTrue("Expected ordered bar targets", first.center.x < second.center.x)
                else assertTrue("Expected ordered rail targets", first.center.y < second.center.y)
            }
        }
        destination("Home").assertIsSelected()
        var selected = "Home"
        for (next in names.drop(1) + "Home") {
            tapNearTop(targets[names.indexOf(next)], viewport)
            destination(next).assertIsSelected()
            destination(selected).assertIsNotSelected()
            selected = next
            val heading = compose.onNode(
                hasTextExactly(selected) and SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading) and textLayout,
                useUnmergedTree = true,
            )
            assertReadable(heading, "$selected heading")
            assertReadable(compose.onNode(hasTextExactly("This section is coming soon.") and textLayout,
                useUnmergedTree = true), "$selected placeholder")
        }
    }

    private fun tapNearTop(target: Rect, viewport: Rect) {
        val inset = with(compose.density) { 4.dp.toPx() }
        val position = Offset(target.center.x - viewport.left, target.top + inset - viewport.top)
        compose.onRoot().performTouchInput { click(position) }
    }

    private fun assertReadable(node: SemanticsNodeInteraction, context: String) {
        val results = mutableListOf<TextLayoutResult>()
        node.assertIsDisplayed().performSemanticsAction(SemanticsActions.GetTextLayoutResult) { action ->
            assertTrue("$context exposes a text layout result", action(results))
        }
        val layout = results.single()
        val visible = node.fetchSemanticsNode().boundsInRoot
        assertEquals("$context uses the configured font scale", MAXIMUM_FONT_SCALE, layout.layoutInput.density.fontScale, 0f)
        assertTrue("$context has text layout overflow", !layout.hasVisualOverflow)
        assertTrue("$context has ellipsized text", (0 until layout.lineCount).none(layout::isLineEllipsized))
        assertTrue("$context layout ${layout.size} is clipped to $visible",
            visible.width >= layout.size.width - 1f && visible.height >= layout.size.height - 1f)
    }

    private fun destination(name: String) = compose.onNode(hasTextExactly(name) and hasClickAction())

    private companion object {
        const val MAXIMUM_FONT_SCALE = 2f
        val textLayout = SemanticsMatcher.keyIsDefined(SemanticsActions.GetTextLayoutResult)
    }
}
