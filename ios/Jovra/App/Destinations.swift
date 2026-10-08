import SwiftUI

// The router's only views: each case maps to the type its owning ticket builds, in that ticket's
// feature folder (`RouteCatalog` names the file). A ticket replaces its file and keeps the type name
// and initializer, so these switches never change after T07.

struct PreShellDestination: View {
    var route: PreShellRoute

    var body: some View {
        switch route {
        case .welcome: WelcomeScreen()
        case .onboarding(let step): OnboardingScreen(step: step)
        }
    }
}

struct SessionsDestination: View {
    var route: SessionsRoute

    var body: some View {
        switch route {
        case .importVideos: ImportScreen()
        case .matchOverview(let session): MatchOverviewScreen(session: session)
        case .practiceOverview(let session): PracticeOverviewScreen(session: session)
        }
    }
}

struct InsightsDestination: View {
    var route: InsightsRoute

    var body: some View {
        switch route {
        case .shotMap(let session): ShotMapScreen(session: session)
        case .serveLab(let session): ServeLabScreen(session: session)
        case .strokeLab(let session): StrokeLabScreen(session: session)
        case .progress: ProgressScreen()
        case .drillDetail(let drill): DrillDetailScreen(drill: drill)
        }
    }
}

struct ProfileDestination: View {
    var route: ProfileRoute

    var body: some View {
        switch route {
        case .racketVault: RacketVaultScreen()
        case .stringJournal: StringJournalScreen()
        case .storage: StorageScreen()
        case .settings: SettingsScreen()
        case .spaceSaver: SpaceSaverScreen()
        case .diagnostics: DiagnosticsScreen()
        case .recordingRules: RecordingRulesScreen()
        }
    }
}

struct FullScreenDestination: View {
    var route: FullScreenRoute

    var body: some View {
        switch route {
        case .capture(let setup): CaptureScreen(setup: setup)
        case .replay(let request): ReplayScreen(request: request)
        case .compare(let comparison): CompareScreen(comparison: comparison)
        case .pointReview(let session, let filter): PointReviewScreen(session: session, filter: filter)
        case .highlightReel(let session): HighlightReelScreen(session: session)
        case .drillSession(let drill): DrillSessionScreen(drill: drill)
        case .processing(let session): ProcessingScreen(session: session)
        }
    }
}

struct SheetDestination: View {
    var route: SheetRoute

    var body: some View {
        switch route {
        case .pointEditor(let session, let point): PointEditorSheet(session: session, point: point)
        case .clipExport(let session, let point): ClipExportSheet(session: session, point: point)
        case .sharePack(let session): SharePackSheet(session: session)
        case .capabilityDetail(let capability): CapabilityDetailSheet(capability: capability)
        case .matchFormat(let context): FormatSheet(context: context)
        case .players: PlayersSheet()
        case .cameraPreset: CameraPresetSheet()
        case .trash: TrashSheet()
        case .goal(let goal): GoalSheet(goal: goal)
        case .consentAttach(let session): ConsentAttachSheet(session: session)
        case .calibration(let session, let time): CalibrationSheet(session: session, time: time)
        case .stringBroke(let session, let time): StringBrokeSheet(session: session, time: time)
        case .restore(let session): RestoreSheet(session: session)
        case .comparisonPicker: ComparisonPickerSheet()
        case .driveAccount: DriveAccountSheet()
        case .account: AccountSheet()
        case .deleteAllData: DeleteAllDataSheet()
        case .permission(let permission): PermissionExplanationSheet(permission: permission)
        }
    }
}
