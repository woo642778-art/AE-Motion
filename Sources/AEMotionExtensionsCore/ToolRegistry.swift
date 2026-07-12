import Foundation

public enum ToolRegistry {
    public static let all: [ToolDescriptor] = [
        .init(id: "speed.remap", title: "Speed Remap Studio", subtitle: "Scroll-locked velocity graph, live preview, Photos import and timeline handoff", section: .extensions),
        .init(id: "easing.curve", title: "Easing Curve Generator", subtitle: "Flow-style editable curves with scroll locking, handles and presets", section: .extensions),
        .init(id: "cutout.person", title: "Person Cutout Studio", subtitle: "Vision cutout with manual selection, automatic tracking and transparent output", section: .extensions),
        .init(id: "depth.map", title: "Depth Map Studio", subtitle: "Automatic relative-depth video with temporal smoothing and timeline return", section: .extensions),
        .init(id: "dead.frames", title: "Dead Frame Cleaner", subtitle: "Detect and remove duplicate frames while keeping audio aligned", section: .extensions),
        .init(id: "camera.shake", title: "Camera Shake Generator", subtitle: "Generate deterministic shake samples", section: .extensions),
        .init(id: "random.values", title: "Random Value Generator", subtitle: "Seeded repeatable random values", section: .scripts),
        .init(id: "expression.helper", title: "Expression Helper", subtitle: "Copy reusable motion formulas", section: .scripts),
        .init(id: "text.animator", title: "Text Animator Presets", subtitle: "Structured text animation recipes", section: .presets),
        .init(id: "motion.presets", title: "Motion Preset Browser", subtitle: "Browse curated motion recipes", section: .presets),
        .init(id: "bpm.frames", title: "BPM / Beat / Frame Calculator", subtitle: "Convert beats, seconds and frames", section: .utilities),
        .init(id: "color.palette", title: "Color Palette Generator", subtitle: "Build harmonic color palettes", section: .utilities),
        .init(id: "layer.offset", title: "Layer Offset Planner", subtitle: "Plan sequential timing offsets", section: .utilities),
        .init(id: "host.diagnostics", title: "Native Host Diagnostics 3", subtitle: "Crash-resistant allowlisted scan for speed, keyframe and timeline bridges", section: .utilities),
    ]
}
