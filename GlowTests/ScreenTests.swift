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
		var retired: [UIViewController] = []
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
			window.rootViewController?.dismiss(animated: false)
			if let old = window.rootViewController { retired.append(old) }
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
		
		shows.stopDemo()
		try await Task.sleep(for: .milliseconds(100))
		window.rootViewController = nil
		window.isHidden = true
		retired = []
		#expect(shown == 3 * 31)
	}
	
	@Test func aShowFilledToTheLimitOpensEveryScreenQuicklyAndStaysResponsiveWithEverySceneRunning() async throws {
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
		let demo = try context.fetch(FetchDescriptor<Fixture>(sortBy: [SortDescriptor(\.sortIndex)]))
		let small = try #require(demo.min { (library.type($0.typeID)?.channelCount ?? 0) < (library.type($1.typeID)?.channelCount ?? 0) })
		let width = small.range(library.type(small.typeID)).count
		var next = (demo.map { $0.range(library.type($0.typeID)).upperBound }.max() ?? 0) + 1
		var added: [Fixture] = []
		
		while next + width - 1 <= Universe.channelCount {
			let fixture = Fixture(typeID: small.typeID, name: "Extra \(added.count + 1)", address: try #require(DMXAddress(next)), sortIndex: Double(demo.count + added.count))
			context.insert(fixture)
			added.append(fixture)
			next += width
		}
		
		let group = FixtureGroup(name: "Everything", sortIndex: 99)
		context.insert(group)
		group.fixtures = demo + added
		let lights = demo + added
		var state: UInt64 = 7
		
		for scene in 0..<30 {
			let look = Look(name: "Full \(scene + 1)", sortIndex: Double(100 + scene))
			context.insert(look)
			
			for number in 0..<40 {
				var levels = Levels()
				
				for light in lights {
					for slot in 1...light.range(library.type(light.typeID)).count {
						state = state &* 6364136223846793005 &+ 1442695040888963407
						levels.set(UInt8(truncatingIfNeeded: state >> 40), slot: slot, of: light.identifier)
					}
				}
				
				let cue = Cue(lookID: look.identifier, sortIndex: Double(number), fade: Double(number % 4), levels: levels)
				cue.follow = number % 3 == 0 ? 0.5 : nil
				context.insert(cue)
			}
		}
		
		try context.save()
		try await Task.sleep(for: .milliseconds(500))
		
		let fixtures = try context.fetch(FetchDescriptor<Fixture>(sortBy: [SortDescriptor(\.sortIndex)]))
		let looks = try context.fetch(FetchDescriptor<Look>(sortBy: [SortDescriptor(\.sortIndex)]))
		let cues = try context.fetch(FetchDescriptor<Cue>(sortBy: [SortDescriptor(\.sortIndex)]))
		let look = try #require(looks.last)
		let held = look.cues(among: cues)
		#expect(fixtures.reduce(0) { $0 + $1.range(library.type($1.typeID)).count } > Universe.channelCount - width)
		#expect(held.count == 40)
		
		let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
		let window = UIWindow(windowScene: scene)
		var retired: [UIViewController] = []
		window.frame = scene.effectiveGeometry.coordinateSpace.bounds
		UIView.setAnimationsEnabled(false)
		defer { UIView.setAnimationsEnabled(true) }
		var slowest: [(String, Duration)] = []
		
		func show(_ name: String, _ content: some View) async throws {
			var took = Duration.seconds(60)
			
			for _ in 0..<3 {
				window.rootViewController?.dismiss(animated: false)
				if let old = window.rootViewController { retired.append(old) }
				let clock = ContinuousClock()
				took = min(took, clock.measure {
					window.rootViewController = UIHostingController(rootView: content.environment(console).environment(library).environment(shows).environment(Arrangement()).modelContainer(shows.container))
					window.makeKeyAndVisible()
					window.layoutIfNeeded()
				})
				try await Task.sleep(for: .milliseconds(50))
			}
			
			print("FULL \(name) \(took)")
			slowest.append((name, took))
		}
		
		for section in [Selection.Section.lights, .scenes, .settings] {
			console.selection.section = section
			try await show("root \(section)", RootView())
		}
		
		group.fixtures.forEach { console.selection.toggle($0) }
		let programmer = console.programmer(among: fixtures, library: library)
		try await show("programmer", Presenter(content: ProgrammerView(programmer: programmer, isSheet: true)))
		try await show("channels", Presenter(content: NavigationStack { ChannelsView(programmer: programmer) }))
		try await show("scene", Presenter(content: SceneView(look: look, isSheet: true)))
		try await show("arrange", Presenter(content: ArrangeView(columns: 4)))
		try await show("store", Presenter(content: StoreView(recording: Recording(.cue(look, after: held.last), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues))))
		try await show("cue", Presenter(content: CueEditView(cue: held[20])))
		try await show("group", Presenter(content: GroupView(group: group)))
		try await show("monitor", Presenter(content: NavigationStack { MonitorView() }))
		console.selection.section = .scenes
		try await show("root scenes again", RootView())
		
		let clock = ContinuousClock()
		let started = clock.measure {
			for list in looks.compactMap({ console.lists[$0.identifier] }) {
				console.go(list)
			}
		}
		
		try await Task.sleep(for: .seconds(1))
		var lag = Duration.zero
		let end = clock.now + .seconds(3)
		
		while clock.now < end {
			try await Task.sleep(for: .milliseconds(10))
			lag = max(lag, clock.measure { window.layoutIfNeeded() })
		}
		
		print("FULL start every scene \(started) worst lag \(lag)")
		#expect(console.playback.playing.count >= looks.count - 1)
		#expect(started < .milliseconds(500))
		#expect(lag < .milliseconds(250))
		
		for (name, took) in slowest {
			#expect(took < .seconds(1), "\(name) took \(took)")
		}
		
		console.stopAll()
		shows.stopDemo()
		try await Task.sleep(for: .milliseconds(100))
		window.rootViewController?.dismiss(animated: false)
		window.rootViewController = nil
		window.isHidden = true
		retired = []
	}
	
	@Test(arguments: [0, 10, 100])
	func switchingTabsInTheSameFrameAsASheetChangeNeverZoomsFromAMissingBar(gap: Int) async throws {
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
		let fixtures = try shows.container.mainContext.fetch(FetchDescriptor<Fixture>(sortBy: [SortDescriptor(\.sortIndex)]))
		let looks = try shows.container.mainContext.fetch(FetchDescriptor<Look>(sortBy: [SortDescriptor(\.sortIndex)]))
		let look = try #require(looks.first { console.lists[$0.identifier].map { $0.cues.count > 1 } == true })
		let list = try #require(console.lists[look.identifier])
		let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
		let window = UIWindow(windowScene: scene)
		window.frame = scene.effectiveGeometry.coordinateSpace.bounds
		window.rootViewController = UIHostingController(rootView: RootView().environment(\.horizontalSizeClass, .compact).environment(console).environment(library).environment(shows).modelContainer(shows.container))
		window.makeKeyAndVisible()
		console.selection.section = .scenes
		try await Task.sleep(for: .milliseconds(500))
		console.go(list)
		
		console.selection.toggle(fixtures[0])
		console.selection.open(scene: look.identifier, isSheet: true)
		try await Task.sleep(for: .milliseconds(800))
		console.selection.section = .lights
		try await Task.sleep(for: .milliseconds(gap))
		console.selection.isProgrammerOpen = true
		try await Task.sleep(for: .milliseconds(gap))
		console.selection.isSceneOpen = false
		try await Task.sleep(for: .milliseconds(1500))
		console.selection.isProgrammerOpen = false
		try await Task.sleep(for: .milliseconds(gap))
		console.selection.section = .scenes
		console.selection.open(scene: look.identifier, isSheet: true)
		try await Task.sleep(for: .milliseconds(800))
		console.selection.section = .settings
		try await Task.sleep(for: .milliseconds(gap))
		console.selection.isSceneOpen = false
		try await Task.sleep(for: .milliseconds(gap))
		console.selection.section = .scenes
		console.selection.open(scene: look.identifier, isSheet: true)
		try await Task.sleep(for: .milliseconds(gap))
		console.selection.section = .lights
		console.selection.isProgrammerOpen = true
		try await Task.sleep(for: .milliseconds(1500))
		
		#expect(!console.selection.isSceneOpen)
		console.stopAll()
		shows.stopDemo()
		try await Task.sleep(for: .milliseconds(100))
		window.rootViewController?.dismiss(animated: false)
		window.rootViewController = nil
		window.isHidden = true
	}
	
	@Test(arguments: [UInt64(1), 2])
	func randomActionsOnOpenScreensWhileOtherDevicesChangeAndDeleteWhatTheyShow(seed: UInt64) async throws {
		var state = seed &* 0x9E3779B97F4A7C15
		
		func roll(_ count: Int) -> Int {
			state = state &* 6364136223846793005 &+ 1442695040888963407
			return Int((state >> 33) % UInt64(max(count, 1)))
		}
		
		func pick<Item>(_ items: [Item]) -> Item? {
			items.isEmpty ? nil : items[roll(items.count)]
		}
		
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
		let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
		let window = UIWindow(windowScene: scene)
		var retired: [UIViewController] = []
		let bounds = scene.effectiveGeometry.coordinateSpace.bounds
		UIView.setAnimationsEnabled(false)
		defer { UIView.setAnimationsEnabled(true) }
		
		var fixtures: [Fixture] { (try? context.fetch(FetchDescriptor<Fixture>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? [] }
		var groups: [FixtureGroup] { (try? context.fetch(FetchDescriptor<FixtureGroup>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? [] }
		var looks: [Look] { (try? context.fetch(FetchDescriptor<Look>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? [] }
		var cues: [Cue] { (try? context.fetch(FetchDescriptor<Cue>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? [] }
		var shown: [any PersistentModel] = []
		
		func remote(_ folder: NodeStore.Folder, _ id: String, _ body: Data?) {
			shows.take(body, at: Wire.Place(show: shows.activeID, folder: folder.rawValue, id: id), in: folder)
		}
		
		func erase(_ model: any PersistentModel) {
			switch model {
			case let look as Look: if !look.isGone { remote(.scenes, look.identifier, nil) }
			case let cue as Cue: if !cue.isDeleted { remote(.cues, cue.identifier, nil) }
			case let fixture as Fixture: if !fixture.isDeleted { remote(.lights, fixture.identifier, nil) }
			case let group as FixtureGroup: if !group.isDeleted { remote(.groups, group.identifier, nil) }
			default: break
			}
		}
		
		func present() async throws {
			let fixtures = fixtures
			let looks = looks
			let cues = cues
			let look = pick(looks)
			let held = look.map { $0.cues(among: cues) } ?? []
			var content: AnyView
			shown = []
			
			switch roll(14) {
			case 0, 1: content = AnyView(RootView())
			case 2, 3: content = AnyView(RootView().environment(\.horizontalSizeClass, .compact))
			case 4: content = AnyView(ProgrammerView(programmer: console.programmer(among: fixtures, library: library), isSheet: true))
			case 5: content = AnyView(NavigationStack { ChannelsView(programmer: console.programmer(among: fixtures, library: library)) })
			case 6: content = AnyView(SceneInspector())
			case 7: content = AnyView(ArrangeView(columns: [2, 4][roll(2)]))
			default:
				if let look, roll(2) == 0 {
					shown = [look] + held
					content = [AnyView(SceneView(look: look, isSheet: true)), AnyView(SceneSettings(look: look)), AnyView(StoreView(recording: Recording(.cue(look, after: held.last), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues)))][roll(3)]
				} else if let cue = pick(held), roll(2) == 0 {
					shown = [cue]
					content = [AnyView(CueEditView(cue: cue)), AnyView(CueTimingSheet(picked: [cue])), AnyView(StoreView(recording: Recording(.into(cue), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues)))][roll(3)]
				} else if let group = pick(groups), roll(2) == 0 {
					shown = [group]
					content = AnyView(GroupView(group: group))
				} else if let fixture = pick(fixtures) {
					shown = [fixture]
					content = AnyView(FixtureEditView(fixture: fixture))
				} else {
					content = AnyView(RootView())
				}
			}
			
			let isNarrow = roll(3) == 0
			window.frame = isNarrow ? CGRect(x: 0, y: 0, width: min(bounds.width, 375), height: bounds.height) : bounds
			window.rootViewController?.dismiss(animated: false)
			if let old = window.rootViewController { retired.append(old) }
			window.rootViewController = UIHostingController(rootView: Presenter(content: content).environment(console).environment(library).environment(shows).environment(Arrangement()).modelContainer(shows.container).dynamicTypeSize([DynamicTypeSize.large, .xSmall, .accessibility3][roll(3)]))
			window.makeKeyAndVisible()
		}
		
		func settle() async throws {
			for _ in 0..<2 {
				window.layoutIfNeeded()
				window.rootViewController?.presentedViewController?.view.layoutIfNeeded()
				try await Task.sleep(for: .milliseconds(5))
			}
		}
		
		var erased = 0
		
		for step in 0..<400 {
			if step % 12 == 0 {
				try await present()
			}
			
			let lists = looks.compactMap { console.lists[$0.identifier] }
			let list = pick(lists)
			
			switch roll(27) {
			case 0: if let list { console.toggle(list) }
			case 1: if let list { console.go(list) }
			case 2: if let list { console.back(list) }
			case 3: if let list { console.flash(list, isHeld: roll(2) == 0) }
			case 4: if let list, !list.cues.isEmpty { console.play(list, at: roll(list.cues.count)) }
			case 5: console.stopAll()
			case 6: if let fixture = pick(fixtures) { console.selection.toggle(fixture) }
			case 7: if let group = pick(groups) { console.selection.toggle(group) }
			case 8: console.selection.section = [Selection.Section.lights, .scenes, .settings][roll(3)]
			case 9: console.selection.isProgrammerOpen = !console.selection.isEmpty && roll(2) == 0
			case 10: if let look = pick(looks) { console.selection.open(scene: look.identifier, isSheet: roll(2) == 0) }
			case 11: if let look = pick(looks) { console.selection.build(look.identifier) } else { console.selection.building = nil }
			case 12: console.selection.building = nil
			case 13, 14:
				if let model = pick(shown), roll(2) == 0 {
					erased += 1
					erase(model)
				} else if let model = pick(Array(fixtures) as [any PersistentModel] + Array(looks) + Array(cues) + Array(groups)) {
					erased += 1
					erase(model)
				}
			case 15:
				for model in shown {
					switch model {
					case let look as Look: look.name = "Typed \(step)"
					case let cue as Cue: cue.label = "Typed \(step)"
					case let fixture as Fixture: fixture.name = "Typed \(step)"
					case let group as FixtureGroup: group.name = "Typed \(step)"
					default: break
					}
				}
			case 16: if context.undoManager?.canUndo == true { context.undoManager?.undo() }
			case 17:
				if let fixture = pick(fixtures) {
					console.set(UInt8(roll(256)), at: fixture.start)
				}
				
				if let look = pick(looks) {
					let cues = cues
					Recording(.cue(look, after: look.cues(among: cues).last), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues).store(context: context)
				}
			case 18: if looks.count < 30 { _ = Look.fresh(among: looks, context: context) }
			case 19: if let look = pick(looks), roll(3) == 0 { console.remove(look, with: cues, context: context) }
			case 20: if let fixture = pick(fixtures), fixtures.count < 40 { console.duplicate(fixture, among: fixtures, library: library, context: context) }
			case 21:
				let programmer = console.programmer(among: fixtures, library: library)
				programmer.setFraction(Double(roll(101)) / 100, for: Attribute.allCases[roll(Attribute.allCases.count)])
			case 22: console.master = Double(roll(101)) / 100
			case 23, 24, 25:
				let odd: [Double] = [.nan, .infinity, -.infinity, -1, 0, 1e300, -1e300, 3601, 0.004]
				let text = ["", " ", String(repeating: "Wide name ", count: 200), "🎭🎛️", "\n\t"][roll(5)]
				var show = ShowContents()
				show.scenes = pick(looks).map { [$0.entry] } ?? []
				show.cues = pick(cues).map { [$0.entry] } ?? []
				show.lights = pick(fixtures).map { [$0.entry] } ?? []
				show.groups = pick(groups).map { [$0.entry] } ?? []
				
				for index in show.scenes.indices {
					show.scenes[index].name = text
					show.scenes[index].sortIndex = odd[roll(odd.count)]
					show.scenes[index].symbol = ["not.a.symbol", "", "star"][roll(3)]
					show.scenes[index].tint = ["nonsense", "", "red"][roll(3)]
					show.scenes[index].buttons = SceneAction.allCases.filter { _ in roll(2) == 0 }
					show.scenes[index].size = TileSize.allCases[roll(TileSize.allCases.count)]
				}
				
				for index in show.cues.indices {
					show.cues[index].label = text
					show.cues[index].sortIndex = odd[roll(odd.count)]
					show.cues[index].fade = odd[roll(odd.count)]
					show.cues[index].delay = odd[roll(odd.count)]
					show.cues[index].follow = roll(2) == 0 ? nil : odd[roll(odd.count)]
					show.cues[index].scene = pick(looks)?.identifier ?? "Nowhere0000"
				}
				
				for index in show.lights.indices {
					show.lights[index].name = text
					show.lights[index].address = [1, 2, 505, 511, 512][roll(5)]
					show.lights[index].sortIndex = [-1e300, 1e300, 0, -5][roll(4)]
					show.lights[index].typeID = roll(4) == 0 ? "missing" : show.lights[index].typeID
					show.lights[index].symbol = roll(2) == 0 ? "not.a.symbol" : nil
				}
				
				for index in show.groups.indices {
					show.groups[index].name = text
					show.groups[index].tint = "nonsense"
				}
				
				for (key, body) in ShowLibrary.encoded(show, folders: ShowLibrary.everything) {
					let parts = key.split(separator: "/", maxSplits: 1)
					guard let folder = NodeStore.Folder(rawValue: String(parts[0])) else { continue }
					remote(folder, String(parts[1]), body)
				}
			default: console.reset(among: fixtures, library: library)
			}
			
			try? context.save()
			try await settle()
		}
		
		#expect(erased > 20)
		console.stopAll()
		shows.stopDemo()
		try await Task.sleep(for: .milliseconds(100))
		window.rootViewController = nil
		window.isHidden = true
		retired = []
	}
	
	@Test(arguments: [UInt64(1), 2, 3].map { $0 + (ProcessInfo.processInfo.environment["GLOW_SEEDS"].flatMap(UInt64.init) ?? 0) })
	func randomTapsSlidesAndTypingAcrossTheWholeAppOnTheDemoShow(seed: UInt64) async throws {
		var state = seed &* 0x9E3779B97F4A7C15
		
		func roll(_ count: Int) -> Int {
			state = state &* 6364136223846793005 &+ 1442695040888963407
			return Int((state >> 33) % UInt64(max(count, 1)))
		}
		
		func pick<Item>(_ items: [Item]) -> Item? {
			items.isEmpty ? nil : items[roll(items.count)]
		}
		
		let console = Console()
		let library = FixtureLibrary()
		let shows = ShowLibrary()
		shows.reach(console, library: library)
		shows.startDemo()
		
		for _ in 0..<300 where !shows.isLoaded {
			try await Task.sleep(for: .milliseconds(10))
		}
		
		#expect(shows.isLoaded)
		let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
		let window = UIWindow(windowScene: scene)
		var retired: [UIViewController] = []
		let bounds = scene.effectiveGeometry.coordinateSpace.bounds
		window.frame = bounds
		UIView.setAnimationsEnabled(false)
		defer { UIView.setAnimationsEnabled(true) }
		let avoided = ["Connect", "Wi-Fi", "Network", "Share", "Save to Files", "Import", "Leave", "Demo", "Password", "Forget", "Stop Using", "Controller"]
		
		func host(compact: Bool) {
			let root = compact ? AnyView(RootView().environment(\.horizontalSizeClass, .compact)) : AnyView(RootView())
			window.frame = compact ? CGRect(x: 0, y: 0, width: min(bounds.width, 390), height: bounds.height) : bounds
			window.rootViewController?.dismiss(animated: false)
			if let old = window.rootViewController { retired.append(old) }
			window.rootViewController = UIHostingController(rootView: root.environment(console).environment(library).environment(shows).modelContainer(shows.container))
			window.makeKeyAndVisible()
		}
		
		func elements(in view: UIView, into found: inout [NSObject]) {
			guard !view.isHidden, view.alpha > 0.01 else { return }
			
			if view.isAccessibilityElement {
				found.append(view)
			}
			
			for element in view.accessibilityElements ?? [] {
				guard let element = element as? NSObject else { continue }
				
				if let inner = element as? UIView {
					elements(in: inner, into: &found)
				} else if element.isAccessibilityElement {
					found.append(element)
				}
			}
			
			for subview in view.subviews {
				elements(in: subview, into: &found)
			}
		}
		
		func focused(in view: UIView) -> UIView? {
			if view.isFirstResponder { return view }
			
			for subview in view.subviews {
				if let found = focused(in: subview) { return found }
			}
			
			return nil
		}
		
		func settle() async throws {
			for _ in 0..<3 {
				for window in scene.windows {
					window.layoutIfNeeded()
				}
				
				try await Task.sleep(for: .milliseconds(8))
			}
		}
		
		let accessibility = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW)
		let automate = unsafeBitCast(try #require(dlsym(accessibility, "_AXSSetAutomationEnabled")), to: (@convention(c) (Int32) -> Void).self)
		automate(1)
		defer { automate(0) }
		host(compact: false)
		try await settle()
		var pressed = 0
		
		for step in 0..<1500 {
			if step % 300 == 150 {
				host(compact: roll(2) == 0)
				try await settle()
			}
			
			if step % 60 == 30 {
				console.selection.section = [Selection.Section.lights, .scenes, .scenes, .settings][roll(4)]
			}
			
			var top: UIViewController? = window.rootViewController
			
			while let next = top?.presentedViewController, !next.isBeingDismissed {
				top = next
			}
			
			var found: [NSObject] = []
			
			if let view = top?.view, top !== window.rootViewController, roll(5) != 0 {
				elements(in: view, into: &found)
			} else {
				elements(in: window, into: &found)
			}
			
			let tabs = ["Lights", "Scenes", "Settings"]
			let usable = found.filter { element in
				let label = element.accessibilityLabel ?? ""
				let traits = element.accessibilityTraits
				let isControl = !traits.isDisjoint(with: [.button, .adjustable, .link, .searchField, .keyboardKey]) || element is UITextField || element is UITextView
				let isTab = tabs.contains(label) && roll(8) != 0
				let isMenu = ProcessInfo.processInfo.isiOSAppOnMac && (element as? UIControl)?.showsMenuAsPrimaryAction == true
				return isControl && !isTab && !isMenu && !label.isEmpty && !avoided.contains { label.localizedCaseInsensitiveContains($0) } && !traits.contains(.notEnabled)
			}
			
			if let responder = scene.windows.lazy.compactMap({ focused(in: $0) }).first as? UIKeyInput, roll(3) == 0 {
				let typed = ["12", "0,5", "3.25", "-7", "99999", "", "Ä🎭", String(repeating: "W", count: 80), "1e9"][roll(9)]
				print("MONKEY \(step) type \(typed.prefix(12))")
				responder.insertText(typed)
				if roll(2) == 0 { responder.insertText("\n") }
				if roll(3) == 0 { (responder as? UIView)?.resignFirstResponder() }
			} else if !usable.isEmpty {
				let element = usable[roll(usable.count)]
				let label = element.accessibilityLabel ?? ""
				
				if let action = pick(element.accessibilityCustomActions ?? []), roll(3) == 0 {
					print("MONKEY \(step) action \(action.name) on \(label)")
					_ = action.actionHandler?(action)
				} else if element.accessibilityTraits.contains(.adjustable), roll(2) == 0 {
					print("MONKEY \(step) adjust \(label)")
					
					for _ in 0...roll(6) {
						if roll(2) == 0 {
							element.accessibilityIncrement()
						} else {
							element.accessibilityDecrement()
						}
					}
				} else {
					print("MONKEY \(step) press \(label)")
					_ = element.accessibilityActivate()
					pressed += 1
				}
			}
			
			if step % 40 == 39, let presented = window.rootViewController?.presentedViewController, roll(2) == 0 {
				print("MONKEY \(step) dismiss")
				presented.dismiss(animated: false)
			}
			
			try await settle()
		}
		
		#expect(pressed > 500)
		console.stopAll()
		shows.stopDemo()
		try await Task.sleep(for: .milliseconds(100))
		window.rootViewController?.dismiss(animated: false)
		window.rootViewController = nil
		window.isHidden = true
		retired = []
	}
	
	@Test func everyScreenOfAnEdgeCaseShowStaysInsideItsWindowAtEveryWidthAndTextSize() async throws {
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
		let long = "Followspot Downstage Centre Left Balcony Rail Position Seven"
		let unbroken = String(repeating: "W", count: 64)
		
		for (index, look) in try context.fetch(FetchDescriptor<Look>(sortBy: [SortDescriptor(\.sortIndex)])).enumerated() {
			look.name = [long, unbroken, "🎭🎛️💡🔦🎬🌈", look.name][index % 4]
		}
		
		for (index, cue) in try context.fetch(FetchDescriptor<Cue>(sortBy: [SortDescriptor(\.sortIndex)])).enumerated() {
			cue.fade = [3600, 59.99, 0.01, cue.fade][index % 4]
			cue.delay = [3600, 0, 1234.56, cue.delay][index % 4]
			cue.follow = [3600, nil, 0, cue.follow][index % 4]
			cue.label = [long, unbroken, "", cue.label][index % 4]
		}
		
		for (index, fixture) in try context.fetch(FetchDescriptor<Fixture>(sortBy: [SortDescriptor(\.sortIndex)])).enumerated() {
			fixture.name = [long, unbroken, fixture.name][index % 3]
		}
		
		for group in try context.fetch(FetchDescriptor<FixtureGroup>()) {
			group.name = long
		}
		
		try context.save()
		try await Task.sleep(for: .milliseconds(300))
		
		let fixtures = try context.fetch(FetchDescriptor<Fixture>(sortBy: [SortDescriptor(\.sortIndex)]))
		let groups = try context.fetch(FetchDescriptor<FixtureGroup>(sortBy: [SortDescriptor(\.sortIndex)]))
		let looks = try context.fetch(FetchDescriptor<Look>(sortBy: [SortDescriptor(\.sortIndex)]))
		let cues = try context.fetch(FetchDescriptor<Cue>(sortBy: [SortDescriptor(\.sortIndex)]))
		let type = try #require(library.builtIn.max { $0.channels.count < $1.channels.count })
		let look = try #require(looks.max { $0.cues(among: cues).count < $1.cues(among: cues).count })
		let held = look.cues(among: cues)
		let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
		let bounds = scene.effectiveGeometry.coordinateSpace.bounds
		let window = UIWindow(windowScene: scene)
		var retired: [UIViewController] = []
		let folder = ProcessInfo.processInfo.environment["GLOW_SNAPSHOTS"].map { $0 == "temporary" ? FileManager.default.temporaryDirectory.appending(path: "GlowSnapshots") : URL(fileURLWithPath: $0) }
		print("SNAPSHOTS \(folder?.path ?? "")")
		let device = ProcessInfo.processInfo.isiOSAppOnMac ? "mac" : UIDevice.current.userInterfaceIdiom == .pad ? "pad" : "phone"
		var outside: [String] = []
		UIView.setAnimationsEnabled(false)
		defer { UIView.setAnimationsEnabled(true) }
		let accessibility = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW)
		let automate = unsafeBitCast(try #require(dlsym(accessibility, "_AXSSetAutomationEnabled")), to: (@convention(c) (Int32) -> Void).self)
		automate(1)
		defer { automate(0) }
		
		func elements(in view: UIView, into found: inout [NSObject]) {
			guard !view.isHidden, view.alpha > 0.01 else { return }
			
			if view.isAccessibilityElement {
				found.append(view)
			}
			
			for element in view.accessibilityElements ?? [] {
				guard let element = element as? NSObject else { continue }
				
				if let inner = element as? UIView {
					elements(in: inner, into: &found)
				} else if element.isAccessibilityElement {
					found.append(element)
				}
			}
			
			for subview in view.subviews {
				elements(in: subview, into: &found)
			}
		}
		
		func settle() async throws {
			for _ in 0..<8 {
				window.layoutIfNeeded()
				window.rootViewController?.presentedViewController?.view.layoutIfNeeded()
				try await Task.sleep(for: .milliseconds(15))
			}
		}
		
		func check(_ name: String, width: CGFloat, size: DynamicTypeSize, isSheet: Bool) async throws {
			if let folder {
				try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
				try Data("\(device) \(Int(width)) \(size) \(name)\n".utf8).write(to: folder.appending(path: "progress.txt"))
			}
			
			try await settle()
			let top = window.rootViewController?.presentedViewController ?? window.rootViewController
			let area = (isSheet ? top?.view : window).map { $0.convert($0.bounds, to: nil) } ?? window.bounds
			var found: [NSObject] = []
			elements(in: top?.view ?? window, into: &found)
			let tag = "\(device) \(Int(width)) \(size) \(name)"
			
			for element in found where !element.accessibilityFrame.isEmpty && !(element.accessibilityLabel ?? "").isEmpty {
				var container: Any? = element
				
				while let next = container, !(next is UIView) {
					container = (next as? NSObject).flatMap { $0.responds(to: NSSelectorFromString("accessibilityContainer")) ? $0.value(forKey: "accessibilityContainer") : nil }
				}
				
				var view = container as? UIView
				var scrolls = false
				
				while let current = view, !scrolls {
					scrolls = (current as? UIScrollView).map { $0.contentSize.width > $0.bounds.width + 1 } ?? false
					view = current.superview
				}
				
				guard !scrolls else { continue }
				let frame = element.accessibilityFrame
				guard frame.minY < area.maxY, frame.maxY > area.minY else { continue }
				guard frame.maxX > area.maxX + 2 || frame.minX < area.minX - 2 else { continue }
				outside.append("\(tag): [\(element.accessibilityLabel ?? "?")] \(Int(frame.minX))...\(Int(frame.maxX)) of \(Int(area.minX))...\(Int(area.maxX))")
			}
			
			guard let folder else { return }
			try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
			let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
				window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
			}
			try image.pngData()?.write(to: folder.appending(path: "\(tag.replacingOccurrences(of: " ", with: "_")).png"))
		}
		
		func host(_ content: some View, width: CGFloat, size: DynamicTypeSize) {
			window.rootViewController?.dismiss(animated: false)
			if let old = window.rootViewController { retired.append(old) }
			window.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
			window.rootViewController = UIHostingController(rootView: content.environment(console).environment(library).environment(shows).environment(Arrangement()).modelContainer(shows.container).dynamicTypeSize(size))
			window.makeKeyAndVisible()
		}
		
		let widths = Array(Set([bounds.width, 320, ProcessInfo.processInfo.isiOSAppOnMac || UIDevice.current.userInterfaceIdiom == .pad ? 700 : bounds.width])).sorted()
		
		for width in widths {
			for size in [DynamicTypeSize.large, .xxxLarge, .accessibility3] {
				console.selection.clear()
				console.selection.building = nil
				
				for section in [Selection.Section.lights, .scenes, .settings] {
					console.selection.section = section
					host(RootView(), width: width, size: size)
					try await check("root \(section)", width: width, size: size, isSheet: false)
				}
				
				for fixture in fixtures {
					console.selection.toggle(fixture)
				}
				
				console.selection.section = .lights
				host(RootView(), width: width, size: size)
				try await check("root selected", width: width, size: size, isSheet: false)
				console.selection.build(look.identifier)
				try await check("root building", width: width, size: size, isSheet: false)
				console.selection.building = nil
				
				let lists = looks.compactMap { console.lists[$0.identifier] }
				
				for list in lists {
					console.toggle(list)
					console.go(list)
				}
				
				console.selection.section = .scenes
				try await check("root scenes playing", width: width, size: size, isSheet: false)
				console.stopAll()
				
				let programmer = console.programmer(among: fixtures, library: library)
				let screens: [(String, AnyView)] = [
					("scene", AnyView(SceneView(look: look, isSheet: true))),
					("programmer", AnyView(ProgrammerView(programmer: programmer, isSheet: true))),
					("channels", AnyView(NavigationStack { ChannelsView(programmer: programmer) })),
					("inspector", AnyView(SceneInspector())),
					("arrange2", AnyView(ArrangeView(columns: 2))),
					("arrange4", AnyView(ArrangeView(columns: 4))),
					("settings scene", AnyView(SceneSettings(look: look))),
					("store new", AnyView(StoreView(recording: Recording(.cue(look, after: held.last), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues)))),
					("store into", AnyView(StoreView(recording: Recording(.into(held[0]), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues)))),
					("cue edit", AnyView(CueEditView(cue: held[0]))),
					("cue timing", AnyView(CueTimingSheet(picked: Array(held.prefix(2))))),
					("fixture edit", AnyView(FixtureEditView(fixture: fixtures[0]))),
					("group", AnyView(GroupView(group: groups[0]))),
					("library", AnyView(NavigationStack { LibraryView(patching: .constant(true)) })),
					("fixture type", AnyView(NavigationStack { FixtureTypeView(type: type, patching: .constant(true)) })),
					("patch", AnyView(PatchView(mode: type, isPresented: .constant(true)))),
					("type editor", AnyView(FixtureTypeEditor(type: type))),
					("channel editor", AnyView(NavigationStack { ChannelEditor(channel: .constant(type.channels[0]), others: type.channels) })),
					("function editor", AnyView(NavigationStack { FunctionEditor(function: .constant(type.channels.flatMap(\.functions).first { !$0.sets.isEmpty } ?? ChannelFunction(from: 0, to: 255, label: "All"))) })),
					("shows", AnyView(NavigationStack { ShowsView() })),
					("node", AnyView(NavigationStack { NodeView() })),
					("password", AnyView(PasswordView())),
					("monitor", AnyView(NavigationStack { MonitorView() })),
					("settings", AnyView(NavigationStack { SettingsView() })),
					("setup", AnyView(NodeSetupView())),
					("waiting", AnyView(WaitingView())),
				]
				
				for (name, screen) in screens {
					host(Presenter(content: screen.dynamicTypeSize(size)), width: width, size: size)
					
					for _ in 0..<100 where window.rootViewController?.presentedViewController == nil {
						try await Task.sleep(for: .milliseconds(10))
					}
					
					try await check(name, width: width, size: size, isSheet: true)
					guard name == "programmer" else { continue }
					
					for feature in FeatureGroup.allCases.dropFirst() {
						var found: [NSObject] = []
						elements(in: window, into: &found)
						_ = found.first { $0.accessibilityLabel == feature.name }?.accessibilityActivate()
						try await check("programmer \(feature.name)", width: width, size: size, isSheet: true)
					}
				}
			}
		}
		
		for line in outside {
			print("OUTSIDE \(line)")
		}
		
		shows.stopDemo()
		try await Task.sleep(for: .milliseconds(100))
		window.rootViewController = nil
		window.isHidden = true
		retired = []
		#expect(outside.isEmpty, "\(outside.count) elements reach past their window")
	}
}
