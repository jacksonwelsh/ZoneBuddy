protocol SpeechCueProviding {
    func speak(_ text: String)
    func stop()
    func startBackgroundKeepAlive()
    func stopBackgroundKeepAlive()
}
