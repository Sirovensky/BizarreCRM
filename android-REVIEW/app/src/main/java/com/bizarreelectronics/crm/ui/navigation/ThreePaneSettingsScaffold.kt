package com.bizarreelectronics.crm.ui.navigation

import androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi
import androidx.compose.material3.adaptive.layout.AnimatedPane
import androidx.compose.material3.adaptive.layout.SupportingPaneScaffoldRole
import androidx.compose.material3.adaptive.navigation.NavigableSupportingPaneScaffold
import androidx.compose.material3.adaptive.navigation.rememberSupportingPaneScaffoldNavigator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier

/**
 * ThreePaneSettingsScaffold -- Section 22 L2236 (plan:L2236)
 *
 * Three-pane Settings layout for XL screens (>=1240 dp):
 *   Main pane       -> top-level Settings categories (Privacy, Notifications, etc.)
 *   Supporting pane -> category items list
 *   Extra pane      -> individual item detail / editor
 *
 * On smaller windows the scaffold gracefully collapses: Medium shows Main+Supporting,
 * Compact shows only the deepest navigated pane.
 *
 * Where to consume:
 * SettingsScreen should check windowMode == Desktop (>=840 dp) and optionally
 * a custom >=1240 dp breakpoint (read LocalConfiguration.current.screenWidthDp)
 * before switching to this scaffold. Example:
 *
 *   val widthDp = LocalConfiguration.current.screenWidthDp
 *   if (widthDp >= 1240) {
 *       ThreePaneSettingsScaffold(
 *           categoriesPane = { SettingsCategoryList(onSelect = { cat -> ... }) },
 *           itemsPane      = { SettingsItemList(category = selectedCat, ...) },
 *           detailPane     = { SettingsItemDetail(item = selectedItem) },
 *           showItems      = selectedCat != null,
 *           showDetail     = selectedItem != null,
 *       )
 *   }
 *
 * @param categoriesPane Top-level category list.
 * @param itemsPane      Category-scoped item list.
 * @param detailPane     Individual item editor / detail view.
 * @param showItems      When true, navigates the scaffold to the Supporting pane.
 * @param showDetail     When true, navigates the scaffold to the Extra pane.
 * @param modifier       Layout modifier.
 */
@OptIn(ExperimentalMaterial3AdaptiveApi::class)
@Composable
fun ThreePaneSettingsScaffold(
    categoriesPane: @Composable () -> Unit,
    itemsPane: @Composable () -> Unit,
    detailPane: @Composable () -> Unit,
    showItems: Boolean,
    showDetail: Boolean,
    modifier: Modifier = Modifier,
) {
    val navigator = rememberSupportingPaneScaffoldNavigator<Nothing>()

    LaunchedEffect(showItems, showDetail) {
        when {
            showDetail -> navigator.navigateTo(SupportingPaneScaffoldRole.Extra)
            showItems  -> navigator.navigateTo(SupportingPaneScaffoldRole.Supporting)
            else       -> navigator.navigateTo(SupportingPaneScaffoldRole.Main)
        }
    }

    NavigableSupportingPaneScaffold(
        navigator = navigator,
        mainPane = {
            AnimatedPane(modifier = Modifier) { categoriesPane() }
        },
        supportingPane = {
            AnimatedPane(modifier = Modifier) { itemsPane() }
        },
        extraPane = {
            AnimatedPane(modifier = Modifier) { detailPane() }
        },
        modifier = modifier,
    )
}
