/// Builds the argv used to launch a service.
///
/// A login + interactive shell loads `.zprofile` and `.zshrc`, so tools installed through
/// nvm / volta / Homebrew are on PATH even though the app was launched from Finder.
public enum ShellCommand {
    public static func arguments(shell: String, directory: String, command: String) -> [String] {
        [shell, "-l", "-i", "-c", "cd \(quote(directory)) && \(command)"]
    }

    /// POSIX single-quote escaping.
    public static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
