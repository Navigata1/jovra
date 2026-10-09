import Foundation
import Darwin

public enum FragmentedMovieLayoutError: Error, Equatable, Sendable {
    case unsafePath, malformedContainer, tooManyBoxes
    case filesystem(Int32)
}

/// Container boundaries only. A complete fragment is not a claim that any video frame decodes.
/// Recovery must separately decode every retained frame before adopting a candidate prefix.
public struct FragmentedMovieLayout: Equatable, Sendable {
    public let completeFragmentEnds: [UInt64]
    public let hasIncompleteTail: Bool

    /// Streams fixed-size box headers, never loading the movie or its payloads into memory.
    public static func inspect(_ url: URL) throws -> FragmentedMovieLayout {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw FragmentedMovieLayoutError.filesystem(errno) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw FragmentedMovieLayoutError.filesystem(errno) }
        guard (info.st_mode & S_IFMT) == S_IFREG, info.st_size > 0 else {
            throw FragmentedMovieLayoutError.unsafePath
        }
        let length = UInt64(info.st_size)
        var offset: UInt64 = 0, boxCount = 0
        var sawFileType = false, sawMovie = false, waitingForMedia = false, incomplete = false
        var ends: [UInt64] = []
        while offset < length {
            boxCount += 1
            guard boxCount <= 100_000 else { throw FragmentedMovieLayoutError.tooManyBoxes }
            guard length - offset >= 8 else { incomplete = true; break }
            try handle.seek(toOffset: offset)
            let header = try read(handle, count: 8)
            let kind = String(bytes: header[4..<8], encoding: .ascii)
            var size = integer(header[0..<4]), headerSize: UInt64 = 8
            if size == 1 {
                guard length - offset >= 16 else { incomplete = true; break }
                size = integer(try read(handle, count: 8)[...]); headerSize = 16
            }
            // Zero means extends to EOF: no independently confirmed fragment boundary exists.
            guard size >= headerSize else { throw FragmentedMovieLayoutError.malformedContainer }
            guard size <= length - offset else { incomplete = true; break }
            switch kind {
            case "ftyp":
                guard offset == 0, !sawFileType else { throw FragmentedMovieLayoutError.malformedContainer }
                sawFileType = true
            case "moov":
                guard sawFileType, !sawMovie, !waitingForMedia, ends.isEmpty else {
                    throw FragmentedMovieLayoutError.malformedContainer
                }
                sawMovie = true
            case "moof":
                guard sawMovie, !waitingForMedia else { throw FragmentedMovieLayoutError.malformedContainer }
                waitingForMedia = true
            case "mdat":
                guard waitingForMedia else { throw FragmentedMovieLayoutError.malformedContainer }
                ends.append(offset + size); waitingForMedia = false
            default:
                guard sawFileType, !waitingForMedia else { throw FragmentedMovieLayoutError.malformedContainer }
            }
            offset += size // Bounded above by length - offset before addition.
        }
        guard sawMovie, !ends.isEmpty else { throw FragmentedMovieLayoutError.malformedContainer }
        return .init(completeFragmentEnds: ends, hasIncompleteTail: incomplete || waitingForMedia)
    }
    private static func read(_ handle: FileHandle, count: Int) throws -> Data {
        guard let bytes = try handle.read(upToCount: count), bytes.count == count else {
            throw FragmentedMovieLayoutError.malformedContainer
        }
        return bytes
    }
    private static func integer(_ bytes: Data.SubSequence) -> UInt64 {
        bytes.reduce(0) { ($0 << 8) | UInt64($1) }
    }
}
