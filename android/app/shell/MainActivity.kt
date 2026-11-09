package com.islanddevcrew.jovra.app.shell

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.annotation.DrawableRes
import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteType
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.window.core.layout.WindowSizeClass
import com.islanddevcrew.jovra.app.R
import com.islanddevcrew.jovra.designsystem.theme.JovraShellTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { JovraShellTheme { JovraShell() } }
    }
}

private enum class ShellDestination(@StringRes val label: Int, @DrawableRes val icon: Int) {
    Home(R.string.shell_home, R.drawable.shell_home),
    Sessions(R.string.shell_sessions, R.drawable.shell_sessions),
    Record(R.string.shell_record, R.drawable.shell_record),
    Insights(R.string.shell_insights, R.drawable.shell_insights),
    Profile(R.string.shell_profile, R.drawable.shell_profile),
}

@Composable
private fun JovraShell() {
    var selected by rememberSaveable { mutableStateOf(ShellDestination.Home) }
    val width = currentWindowAdaptiveInfo().windowSizeClass
    val navigation = if (width.isWidthAtLeastBreakpoint(WindowSizeClass.WIDTH_DP_MEDIUM_LOWER_BOUND)) {
        NavigationSuiteType.NavigationRail
    } else {
        NavigationSuiteType.NavigationBar
    }

    NavigationSuiteScaffold(
        navigationSuiteItems = {
            ShellDestination.entries.forEach { destination ->
                item(
                    selected = selected == destination,
                    onClick = { selected = destination },
                    icon = { Icon(painterResource(destination.icon), contentDescription = null) },
                    label = { Text(stringResource(destination.label)) },
                )
            }
        },
        layoutType = navigation,
        containerColor = MaterialTheme.colorScheme.background,
        contentColor = MaterialTheme.colorScheme.onBackground,
    ) {
        Column(
            modifier = Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(stringResource(R.string.shell_app_name), style = MaterialTheme.typography.labelLarge)
            Text(
                stringResource(selected.label),
                modifier = Modifier.semantics { heading() },
                style = MaterialTheme.typography.headlineLarge,
            )
            Text(stringResource(R.string.shell_placeholder), style = MaterialTheme.typography.bodyLarge)
        }
    }
}
