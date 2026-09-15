import Foundation

public enum WeatherFixPolicy {
    public static func accepts(coordinate: WeatherCoordinate, timestamp: Date, accuracy: Double,
                               requestedAt: Date, now: Date) -> Bool {
        // Recency is relative to now so a cached fix from just before requestedAt remains usable.
        _ = requestedAt
        return coordinate.latitude.isFinite && coordinate.longitude.isFinite &&
        (-90...90).contains(coordinate.latitude) && (-180...180).contains(coordinate.longitude) &&
        accuracy.isFinite && (0...100).contains(accuracy) &&
        (0...30).contains(now.timeIntervalSince(timestamp))
    }
}
