import LociModel

/// What a model is asked to tidy a piece of an article with, and how its answer is read. The tidy stage checks
/// the answer against the piece with `ArticleTidying` before using it.
enum TidyPrompt {
  static func request(for piece: String, title: String) -> String {
    """
    Below is a piece of the article "\(title)" in Markdown, taken from a web page. Tidy it so it reads as a clean \
    article, and change nothing else:

    - Remove what the web site put around the text: navigation, dates and category links before the text, \
    "share" and "open in a new window" labels, author and acknowledgement boxes, and "continue reading" or \
    related-article cards after it.
    - Set headings to one consistent level order. A line that only names a code block's language or file becomes \
    the block's fence language; a file name may stay as plain text above the block.
    - Remove a caption that repeats the picture's own description word for word. Join links that were broken \
    into pieces.
    - Keep every sentence of the article, in its own language; do not translate, summarize, reword or add anything.
    - Keep every picture exactly as written, keep every code block's content character for character, and keep \
    link addresses as they are; add no new links.

    Return only one JSON object, no prose around it: {"markdown": "…"}

    The piece:
    \(TranscriptPrompts.json(["markdown": piece]))
    """
  }

  static func markdown(in reply: String) throws(TranscriptAnswerError) -> String {
    struct Answer: Decodable { let markdown: String }
    let markdown = try TranscriptAnswers.decode(Answer.self, from: reply).markdown
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !markdown.isEmpty else { throw TranscriptAnswerError("the tidied text came back empty") }
    return markdown
  }
}
