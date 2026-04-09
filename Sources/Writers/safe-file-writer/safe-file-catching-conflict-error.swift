import Foundation
import Difference

public extension SafeFileOverwriteConflict {
    @inlinable
    func renderedLayout(
        options: SafeFileDiffRenderOptions = .unified,
        using renderer: (SafeFileDiffLayout) -> String
    ) -> String? {
        guard let layout = layout(options: options) else {
            return nil
        }

        return renderer(layout)
    }

    @inlinable
    func renderedDifference(
        using renderer: (SafeFileDifference) -> String
    ) -> String? {
        guard let difference else {
            return nil
        }

        return renderer(difference)
    }

    @inlinable
    func renderedDifference<Renderer: DifferenceRendering>(
        using renderer: Renderer.Type
    ) -> String? {
        guard let difference else {
            return nil
        }

        return Renderer.render(difference)
    }
}

extension StandardWriter {
    public struct WriterWithCatchingErrorAPI {
        public let writer: StandardWriter

        public init(
            writer: StandardWriter
        ) {
            self.writer = writer
        }

        // MARK: - Layer 1: raw conflict callback

        @discardableResult
        @inlinable
        public func write_and_catch<T>(
            _ operation: () throws -> T,
            onConflict: (SafeFileOverwriteConflict) -> Void
        ) throws -> T {
            do {
                return try operation()
            } catch let error as SafeFileError {
                if let conflict = error.overwriteConflictValue {
                    onConflict(conflict)
                }

                throw error
            } catch {
                throw error
            }
        }

        // MARK: - Layer 2: rendered callback via closure

        @discardableResult
        @inlinable
        public func write_and_catch<T>(
            _ operation: () throws -> T,
            renderDifference: (SafeFileDifference) -> String,
            onRenderedConflict: (String, SafeFileOverwriteConflict) -> Void
        ) throws -> T {
            try write_and_catch(
                operation,
                onConflict: { conflict in
                    guard let rendered = conflict.renderedDifference(using: renderDifference) else {
                        return
                    }

                    onRenderedConflict(
                        rendered,
                        conflict
                    )
                }
            )
        }

        @discardableResult
        @inlinable
        public func write_and_catch<T>(
            _ operation: () throws -> T,
            renderDifference: (SafeFileDifference) -> String,
            onRenderedConflict: (String) -> Void
        ) throws -> T {
            try write_and_catch(
                operation,
                renderDifference: renderDifference,
                onRenderedConflict: { rendered, _ in
                    onRenderedConflict(rendered)
                }
            )
        }

        // MARK: - Layer 3: rendered callback via renderer type

        @discardableResult
        @inlinable
        public func write_and_catch<T, Renderer: DifferenceRendering>(
            _ operation: () throws -> T,
            renderer: Renderer.Type,
            onRenderedConflict: (String, SafeFileOverwriteConflict) -> Void
        ) throws -> T {
            try write_and_catch(
                operation,
                renderDifference: { difference in
                    Renderer.render(difference)
                },
                onRenderedConflict: onRenderedConflict
            )
        }

        @discardableResult
        @inlinable
        public func write_and_catch<T, Renderer: DifferenceRendering>(
            _ operation: () throws -> T,
            renderer: Renderer.Type,
            onRenderedConflict: (String) -> Void
        ) throws -> T {
            try write_and_catch(
                operation,
                renderer: renderer,
                onRenderedConflict: { rendered, _ in
                    onRenderedConflict(rendered)
                }
            )
        }

        // MARK: - Layer 4: direct forwarding write APIs

        @discardableResult
        @inlinable
        public func write(
            _ data: Data,
            options: SafeWriteOptions = .init(),
            onConflict: (SafeFileOverwriteConflict) -> Void
        ) throws -> SafeWriteResult {
            try write_and_catch(
                {
                    try writer.write(
                        data,
                        options: options
                    )
                },
                onConflict: onConflict
            )
        }

        @discardableResult
        @inlinable
        public func write<Renderer: DifferenceRendering>(
            _ data: Data,
            options: SafeWriteOptions = .init(),
            renderer: Renderer.Type,
            onRenderedConflict: (String, SafeFileOverwriteConflict) -> Void
        ) throws -> SafeWriteResult {
            try write_and_catch(
                {
                    try writer.write(
                        data,
                        options: options
                    )
                },
                renderer: renderer,
                onRenderedConflict: onRenderedConflict
            )
        }

        @discardableResult
        @inlinable
        public func write<Renderer: DifferenceRendering>(
            _ data: Data,
            options: SafeWriteOptions = .init(),
            renderer: Renderer.Type,
            onRenderedConflict: (String) -> Void
        ) throws -> SafeWriteResult {
            try write_and_catch(
                {
                    try writer.write(
                        data,
                        options: options
                    )
                },
                renderer: renderer,
                onRenderedConflict: onRenderedConflict
            )
        }

        @discardableResult
        @inlinable
        public func write(
            _ string: String,
            encoding: String.Encoding = .utf8,
            options: SafeWriteOptions = .init(),
            onConflict: (SafeFileOverwriteConflict) -> Void
        ) throws -> SafeWriteResult {
            try write_and_catch(
                {
                    try writer.write(
                        string,
                        encoding: encoding,
                        options: options
                    )
                },
                onConflict: onConflict
            )
        }

        @discardableResult
        @inlinable
        public func write<Renderer: DifferenceRendering>(
            _ string: String,
            encoding: String.Encoding = .utf8,
            options: SafeWriteOptions = .init(),
            renderer: Renderer.Type,
            onRenderedConflict: (String, SafeFileOverwriteConflict) -> Void
        ) throws -> SafeWriteResult {
            try write_and_catch(
                {
                    try writer.write(
                        string,
                        encoding: encoding,
                        options: options
                    )
                },
                renderer: renderer,
                onRenderedConflict: onRenderedConflict
            )
        }

        @discardableResult
        @inlinable
        public func write<Renderer: DifferenceRendering>(
            _ string: String,
            encoding: String.Encoding = .utf8,
            options: SafeWriteOptions = .init(),
            renderer: Renderer.Type,
            onRenderedConflict: (String) -> Void
        ) throws -> SafeWriteResult {
            try write_and_catch(
                {
                    try writer.write(
                        string,
                        encoding: encoding,
                        options: options
                    )
                },
                renderer: renderer,
                onRenderedConflict: onRenderedConflict
            )
        }

        @discardableResult
        @inlinable
        public func write(
            _ string: String,
            content mode: ContentOverwriteMode,
            separator: String? = nil,
            encoding: String.Encoding = .utf8,
            options: SafeWriteOptions = .init(),
            onConflict: (SafeFileOverwriteConflict) -> Void
        ) throws -> SafeWriteResult {
            try write_and_catch(
                {
                    try writer.write(
                        string,
                        content: mode,
                        separator: separator,
                        encoding: encoding,
                        options: options
                    )
                },
                onConflict: onConflict
            )
        }

        @discardableResult
        @inlinable
        public func write<Renderer: DifferenceRendering>(
            _ string: String,
            content mode: ContentOverwriteMode,
            separator: String? = nil,
            encoding: String.Encoding = .utf8,
            options: SafeWriteOptions = .init(),
            renderer: Renderer.Type,
            onRenderedConflict: (String, SafeFileOverwriteConflict) -> Void
        ) throws -> SafeWriteResult {
            try write_and_catch(
                {
                    try writer.write(
                        string,
                        content: mode,
                        separator: separator,
                        encoding: encoding,
                        options: options
                    )
                },
                renderer: renderer,
                onRenderedConflict: onRenderedConflict
            )
        }

        @discardableResult
        @inlinable
        public func write<Renderer: DifferenceRendering>(
            _ string: String,
            content mode: ContentOverwriteMode,
            separator: String? = nil,
            encoding: String.Encoding = .utf8,
            options: SafeWriteOptions = .init(),
            renderer: Renderer.Type,
            onRenderedConflict: (String) -> Void
        ) throws -> SafeWriteResult {
            try write_and_catch(
                {
                    try writer.write(
                        string,
                        content: mode,
                        separator: separator,
                        encoding: encoding,
                        options: options
                    )
                },
                renderer: renderer,
                onRenderedConflict: onRenderedConflict
            )
        }
    }

    public var catching: WriterWithCatchingErrorAPI {
        .init(writer: self)
    }
}
