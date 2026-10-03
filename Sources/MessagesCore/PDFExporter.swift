import AppKit
import CoreText

public enum PDFExporter {
    public static func makePDF(
        title: String,
        messages: [Message],
        to url: URL,
        displayName: (Message) -> String = { $0.sender }
    ) {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let textRect = mediaBox.insetBy(dx: 54, dy: 54)

        guard let consumer = CGDataConsumer(url: url as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        let fullText = NSMutableAttributedString()
        fullText.append(NSAttributedString(string: title + "\n\n", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 18)
        ]))
        for message in messages {
            fullText.append(NSAttributedString(
                string: "\(displayName(message)) — \(dateFormatter.string(from: message.date))\n",
                attributes: [.font: NSFont.boldSystemFont(ofSize: 9), .foregroundColor: NSColor.darkGray]
            ))
            fullText.append(NSAttributedString(
                string: message.text + "\n\n",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.black]
            ))
        }

        let framesetter = CTFramesetterCreateWithAttributedString(fullText)
        let path = CGPath(rect: textRect, transform: nil)
        var location = 0
        let totalLength = fullText.length

        while location < totalLength {
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            ctx.beginPDFPage(nil)
            CTFrameDraw(frame, ctx)
            ctx.endPDFPage()

            let visibleRange = CTFrameGetVisibleStringRange(frame)
            guard visibleRange.length > 0 else { break } // nothing more fits — stop instead of looping forever
            location += visibleRange.length
        }
        ctx.closePDF()
    }
}
