//
//  TransferRateEstimator.swift
//  NearbyShare
//

import Foundation

/// Estimates transfer throughput and remaining time from byte-progress samples.
/// The estimator is intentionally UI-free and takes the clock as a parameter so
/// its behavior stays deterministic in tests.
public final class TransferRateEstimator{
	/// Samples closer together than this are ignored so bursty progress
	/// callbacks cannot distort the measured rate.
	private static let minimumSampleInterval:Double=0.25
	private let smoothingFactor:Double
	private var lastTime:Double?
	private var lastBytes:Double=0
	private var smoothedRate:Double?

	public init(smoothingFactor:Double=0.3){
		self.smoothingFactor=smoothingFactor
	}

	/// The smoothed throughput in bytes per second, if at least two
	/// sufficiently spaced samples have been recorded.
	public var rate:Double?{smoothedRate}

	/// Records a progress sample. `time` defaults to the system uptime so wall
	/// clock changes cannot corrupt the measurement.
	/// - Returns: the smoothed rate after this sample, or the previous rate when
	///   the sample was too soon to be used.
	@discardableResult public func update(bytes:Double, at time:Double = ProcessInfo.processInfo.systemUptime) -> Double?{
		guard bytes.isFinite, time.isFinite else{return smoothedRate}
		if bytes<lastBytes{
			// A new attempt restarted from the beginning; forget the old rate.
			reset()
			lastTime=time
			lastBytes=bytes
			return nil
		}
		guard let previousTime=lastTime else{
			lastTime=time
			lastBytes=bytes
			return nil
		}
		let interval=time-previousTime
		guard interval>=Self.minimumSampleInterval else{return smoothedRate}
		let previousBytes=lastBytes
		lastTime=time
		lastBytes=bytes
		let instant=(bytes-previousBytes)/interval
		let smoothed=smoothedRate.map {smoothingFactor*instant+(1-smoothingFactor)*$0} ?? instant
		smoothedRate=smoothed
		return smoothed
	}

	/// The expected remaining time based on the latest smoothed rate.
	/// Returns nil while no reliable rate is known or the transfer is done.
	public func estimatedRemaining(totalBytes:Double)->TimeInterval?{
		guard totalBytes.isFinite, totalBytes>0, lastBytes<totalBytes else{return nil}
		guard let rate=smoothedRate, rate>0 else{return nil}
		return (totalBytes-lastBytes)/rate
	}

	public func reset(){
		lastTime=nil
		lastBytes=0
		smoothedRate=nil
	}
}

/// Formats throughput and remaining time for progress UI. The surrounding
/// views own the layout; this only keeps the wording consistent everywhere a
/// transfer reports progress.
public enum TransferRateFormat{
	public static func speed(_ bytesPerSecond:Double)->String{
		guard bytesPerSecond.isFinite else{return ""}
		let clamped=max(0, min(bytesPerSecond, Double(Int64.max)))
		return ByteCountFormatter.string(fromByteCount: Int64(clamped), countStyle: .file)+"/s"
	}

	public static func remaining(_ seconds:TimeInterval)->String{
		guard seconds.isFinite else{return ""}
		// Clamp so the conversion to Int can never overflow on absurd estimates.
		let rounded=max(1, Int(min(seconds, 365*24*3600).rounded()))
		if rounded<60{
			return String(format: NSLocalizedString("TimeRemainingSeconds", value: "About %d sec remaining", comment: ""), rounded)
		}
		if rounded<3600{
			return String(format: NSLocalizedString("TimeRemainingMinutes", value: "About %d min remaining", comment: ""), max(1, (rounded+30)/60))
		}
		return String(format: NSLocalizedString("TimeRemainingHours", value: "About %d h remaining", comment: ""), max(1, (rounded+1800)/3600))
	}
}
