import SwiftUI

public enum TVMotion {
    public static let focus = Animation.spring(response: 0.26, dampingFraction: 0.80, blendDuration: 0.04)
    public static let hero = Animation.easeInOut(duration: 0.42)
    public static let runtime = Animation.spring(response: 0.38, dampingFraction: 0.82, blendDuration: 0.08)
}
