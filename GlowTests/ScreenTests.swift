import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import Glow

private struct Presenter<Content: View>: View {
	let content: Content
	
	@State private var isOpen = false
	
	var body: some View {
		TabView {
			Tab("Sheet", systemImage: "rectangle.portrait") {
				NavigationStack {
					Color.clear
						.sheet(isPresented: $isOpen) {
							content
						}
						.task {
							isOpen = true
						}
				}
			}
		}
	}
}

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GLOW_SCREENS"] != nil))
struct ScreenTests {
	@Test func everyScreenAndSheetOpensOnTheDemoShowInEveryLookAndSize() async throws {
		let console = Console()
		let library = FixtureLibrary()
		let shows = ShowLibrary()
		shows.reach(console, library: library)
		shows.startDemo()
		
		for _ in 0..<300 where !shows.isLoaded {
			try await Task.sleep(for: .milliseconds(10))
		}
		
		#expect(shows.isLoaded)
		try await Task.sleep(for: .milliseconds(300))
		
		let context = shows.container.mainContext
		let fixtures = try context.fetch(FetchDescriptor<Fixture>(sortBy: [SortDescriptor(\.sortIndex)]))
		let groups = try context.fetch(FetchDescriptor<FixtureGroup>(sortBy: [SortDescriptor(\.sortIndex)]))
		let looks = try context.fetch(FetchDescriptor<Look>(sortBy: [SortDescriptor(\.sortIndex)]))
		let cues = try context.fetch(FetchDescriptor<Cue>(sortBy: [SortDescriptor(\.sortIndex)]))
		let type = try #require(library.builtIn.first { $0.movesHead })
		let look = try #require(looks.first { look in cues.filter { $0.lookID == look.identifier }.count > 2 })
		let held = cues.filter { $0.lookID == look.identifier }
		#expect(!fixtures.isEmpty && !groups.isEmpty)
		
		let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
		let window = UIWindow(windowScene: scene)
		window.frame = scene.coordinateSpace.bounds
		UIView.setAnimationsEnabled(false)
		defer { UIView.setAnimationsEnabled(true) }
		
		var shown = 0
		
		func settle() async throws {
			for _ in 0..<6 {
				window.layoutIfNeeded()
				try await Task.sleep(for: .milliseconds(15))
			}
		}
		
		func show(_ content: some View, size: DynamicTypeSize, scheme: ColorScheme) async throws {
			window.rootViewController = UIHostingController(rootView: content.environment(console).environment(library).environment(shows).environment(Arrangement()).modelContainer(shows.container).dynamicTypeSize(size).preferredColorScheme(scheme))
			window.makeKeyAndVisible()
			try await settle()
			shown += 1
		}
		
		func sheet(_ content: some View, size: DynamicTypeSize, scheme: ColorScheme) async throws {
			try await show(Presenter(content: content), size: size, scheme: scheme)
			
			for _ in 0..<100 where window.rootViewController?.presentedViewController == nil {
				try await Task.sleep(for: .milliseconds(10))
			}
			
			#expect(window.rootViewController?.presentedViewController != nil)
			try await settle()
		}
		
		for (size, scheme) in [(DynamicTypeSize.large, ColorScheme.light), (.xSmall, .dark), (.accessibility5, .light)] {
			console.selection.clear()
			console.selection.building = nil
			
			for section in [Selection.Section.lights, .scenes, .settings] {
				console.selection.section = section
				try await show(RootView(), size: size, scheme: scheme)
			}
			
			for fixture in fixtures {
				console.selection.toggle(fixture)
			}
			
			try await show(RootView().environment(\.horizontalSizeClass, .compact), size: size, scheme: scheme)
			console.selection.section = .lights
			console.selection.isProgrammerOpen = true
			try await settle()
			#expect(window.rootViewController?.presentedViewController != nil)
			console.selection.isProgrammerOpen = false
			try await settle()
			console.selection.section = .scenes
			console.selection.open(scene: look.identifier, isSheet: true)
			try await settle()
			#expect(window.rootViewController?.presentedViewController != nil)
			
			for list in looks.compactMap({ console.lists[$0.identifier] }) {
				console.toggle(list)
				console.go(list)
			}
			
			try await settle()
			console.go(try #require(console.lists[look.identifier]))
			console.selection.isSceneOpen = false
			console.selection.build(look.identifier)
			try await settle()
			console.selection.building = nil
			console.stopAll()
			try await settle()
			
			let programmer = console.programmer(among: fixtures, library: library)
			let screens: [AnyView] = [
				AnyView(SceneView(look: look, isSheet: true)),
				AnyView(ProgrammerView(programmer: programmer, isSheet: true)),
				AnyView(NavigationStack { ChannelsView(programmer: programmer) }),
				AnyView(SceneInspector()),
				AnyView(ArrangeView(columns: 2)),
				AnyView(ArrangeView(columns: 4)),
				AnyView(SceneSettings(look: look)),
				AnyView(StoreView(recording: Recording(.cue(look, after: held.last), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues))),
				AnyView(StoreView(recording: Recording(.into(held[0]), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues))),
				AnyView(CueEditView(cue: held[1])),
				AnyView(CueTimingSheet(picked: Array(held.prefix(2)))),
				AnyView(FixtureEditView(fixture: fixtures[0])),
				AnyView(GroupView(group: groups[0])),
				AnyView(NavigationStack { LibraryView(patching: .constant(true)) }),
				AnyView(NavigationStack { FixtureTypeView(type: type, patching: .constant(true)) }),
				AnyView(PatchView(mode: type, isPresented: .constant(true))),
				AnyView(FixtureTypeEditor()),
				AnyView(FixtureTypeEditor(type: type)),
				AnyView(NavigationStack { ChannelEditor(channel: .constant(type.channels[0]), others: type.channels) }),
				AnyView(NavigationStack { FunctionEditor(function: .constant(type.channels.flatMap(\.functions).first { !$0.sets.isEmpty } ?? ChannelFunction(from: 0, to: 255, label: "All"))) }),
				AnyView(NavigationStack { ShowsView() }),
				AnyView(NavigationStack { NodeView() }),
				AnyView(PasswordView()),
				AnyView(NavigationStack { MonitorView() }),
				AnyView(NavigationStack { SettingsView() }),
				AnyView(NodeSetupView()),
				AnyView(WaitingView()),
			]
			
			for screen in screens {
				try await sheet(screen, size: size, scheme: scheme)
			}
		}
		
		window.rootViewController = nil
		window.isHidden = true
		shows.stopDemo()
		#expect(shown == 3 * 31)
	}
}
