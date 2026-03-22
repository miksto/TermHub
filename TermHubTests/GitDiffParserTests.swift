import Testing

@testable import TermHub

@Suite("GitDiff Parser Tests")
struct GitDiffParserTests {
    @Test("Empty input returns empty diff")
    func emptyInput() {
        let diff = GitService.parseDiff("")
        #expect(diff.files.isEmpty)
    }

    @Test("Single file with one hunk")
    func singleFileOneHunk() {
        let raw = """
            diff --git a/hello.txt b/hello.txt
            index 1234567..abcdefg 100644
            --- a/hello.txt
            +++ b/hello.txt
            @@ -1,3 +1,4 @@
             line one
            -line two
            +line two modified
            +line two added
             line three
            """
        let diff = GitService.parseDiff(raw)
        #expect(diff.files.count == 1)

        let file = diff.files[0]
        #expect(file.oldPath == "hello.txt")
        #expect(file.newPath == "hello.txt")
        #expect(file.isBinary == false)
        #expect(file.hunks.count == 1)
        #expect(file.linesAdded == 2)
        #expect(file.linesDeleted == 1)

        let lines = file.hunks[0].lines
        #expect(lines.count == 5)
        #expect(lines[0].type == .context)
        #expect(lines[0].content == "line one")
        #expect(lines[0].oldLineNumber == 1)
        #expect(lines[0].newLineNumber == 1)
        #expect(lines[1].type == .removed)
        #expect(lines[1].oldLineNumber == 2)
        #expect(lines[1].newLineNumber == nil)
        #expect(lines[2].type == .added)
        #expect(lines[2].oldLineNumber == nil)
        #expect(lines[2].newLineNumber == 2)
        #expect(lines[3].type == .added)
        #expect(lines[3].newLineNumber == 3)
        #expect(lines[4].type == .context)
        #expect(lines[4].content == "line three")
        #expect(lines[4].oldLineNumber == 3)
        #expect(lines[4].newLineNumber == 4)
    }

    @Test("Multiple files")
    func multipleFiles() {
        let raw = """
            diff --git a/file1.txt b/file1.txt
            --- a/file1.txt
            +++ b/file1.txt
            @@ -1,2 +1,2 @@
            -old
            +new
             same
            diff --git a/file2.txt b/file2.txt
            --- a/file2.txt
            +++ b/file2.txt
            @@ -1 +1,2 @@
             existing
            +added
            """
        let diff = GitService.parseDiff(raw)
        #expect(diff.files.count == 2)
        #expect(diff.files[0].newPath == "file1.txt")
        #expect(diff.files[1].newPath == "file2.txt")
        #expect(diff.files[0].linesAdded == 1)
        #expect(diff.files[0].linesDeleted == 1)
        #expect(diff.files[1].linesAdded == 1)
        #expect(diff.files[1].linesDeleted == 0)
    }

    @Test("Binary file detection")
    func binaryFile() {
        let raw = """
            diff --git a/image.png b/image.png
            Binary files a/image.png and b/image.png differ
            """
        let diff = GitService.parseDiff(raw)
        #expect(diff.files.count == 1)
        #expect(diff.files[0].isBinary == true)
        #expect(diff.files[0].hunks.isEmpty)
    }

    @Test("New file (from /dev/null)")
    func newFile() {
        let raw = """
            diff --git a/new.txt b/new.txt
            new file mode 100644
            --- /dev/null
            +++ b/new.txt
            @@ -0,0 +1,2 @@
            +first line
            +second line
            """
        let diff = GitService.parseDiff(raw)
        #expect(diff.files.count == 1)
        #expect(diff.files[0].oldPath == "/dev/null")
        #expect(diff.files[0].newPath == "new.txt")
        #expect(diff.files[0].linesAdded == 2)
    }

    @Test("Deleted file (to /dev/null)")
    func deletedFile() {
        let raw = """
            diff --git a/old.txt b/old.txt
            deleted file mode 100644
            --- a/old.txt
            +++ /dev/null
            @@ -1,2 +0,0 @@
            -first line
            -second line
            """
        let diff = GitService.parseDiff(raw)
        #expect(diff.files.count == 1)
        #expect(diff.files[0].oldPath == "old.txt")
        #expect(diff.files[0].newPath == "/dev/null")
        #expect(diff.files[0].linesDeleted == 2)
    }

    @Test("No newline at end of file marker is skipped")
    func noNewlineMarker() {
        let raw = """
            diff --git a/file.txt b/file.txt
            --- a/file.txt
            +++ b/file.txt
            @@ -1,2 +1,2 @@
            -old line
            +new line
            \\ No newline at end of file
            """
        let diff = GitService.parseDiff(raw)
        let lines = diff.files[0].hunks[0].lines
        #expect(lines.count == 2)
        #expect(lines[0].type == .removed)
        #expect(lines[1].type == .added)
    }

    @Test("Multiple hunks in one file")
    func multipleHunks() {
        let raw = """
            diff --git a/file.txt b/file.txt
            --- a/file.txt
            +++ b/file.txt
            @@ -1,3 +1,3 @@
             context
            -removed
            +added
             context
            @@ -10,3 +10,3 @@
             more context
            -another removed
            +another added
             more context
            """
        let diff = GitService.parseDiff(raw)
        #expect(diff.files[0].hunks.count == 2)
        #expect(diff.files[0].hunks[0].oldStart == 1)
        #expect(diff.files[0].hunks[0].newStart == 1)
        #expect(diff.files[0].hunks[1].oldStart == 10)
        #expect(diff.files[0].hunks[1].newStart == 10)
    }

    @Test("Line number tracking across added and removed lines")
    func lineNumberTracking() {
        let raw = """
            diff --git a/file.txt b/file.txt
            --- a/file.txt
            +++ b/file.txt
            @@ -5,4 +5,5 @@
             context
            -removed1
            -removed2
            +added1
            +added2
            +added3
             context
            """
        let diff = GitService.parseDiff(raw)
        let lines = diff.files[0].hunks[0].lines

        // Context line at old:5, new:5
        #expect(lines[0].oldLineNumber == 5)
        #expect(lines[0].newLineNumber == 5)

        // Removed lines at old:6, old:7
        #expect(lines[1].oldLineNumber == 6)
        #expect(lines[2].oldLineNumber == 7)

        // Added lines at new:6, new:7, new:8
        #expect(lines[3].newLineNumber == 6)
        #expect(lines[4].newLineNumber == 7)
        #expect(lines[5].newLineNumber == 8)

        // Final context at old:8, new:9
        #expect(lines[6].oldLineNumber == 8)
        #expect(lines[6].newLineNumber == 9)
    }
}
