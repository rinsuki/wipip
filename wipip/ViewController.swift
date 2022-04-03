//
//  ViewController.swift
//  wipip
//
//  Created by user on 2022/04/02.
//

import Cocoa
import ScreenCaptureKit
import AVKit

class PreviewView: NSView {
    var displayLayer = AVSampleBufferDisplayLayer()
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer = displayLayer
        wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class ViewController: NSViewController {
    @IBOutlet weak var selectWindowButton: NSPopUpButton!
    @IBOutlet weak var refershButton: NSButton!
    let previewView = PreviewView()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        view.addSubview(previewView)
        previewView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        previewView.layer?.zPosition = -1
        refresh(nil)
    }
    
    override func viewDidAppear() {
        view.window?.isMovableByWindowBackground = true
        view.window?.level = .popUpMenu
        view.window?.delegate = self
    }

    @IBAction func refresh(_ sender: Any?) {
        Task {
            let sharableContent = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            print(sharableContent.displays)
            var items: [NSMenuItem] = []
            for display in sharableContent.displays {
                let item = NSMenuItem(title: display.displayID.description, action: nil, keyEquivalent: "")
                item.representedObject = display
                items.append(item)
            }
            items.append(.separator())
            // we need this for filter outs menu-bar items
            // for MacBook Pros with notch, it will going to 43 on max resolution
            for window in sharableContent.windows where window.frame.size.height > 48 {
                var title = window.title ?? "(Untitled)"
                if let appTitle = window.owningApplication?.applicationName {
                    title += " — \(appTitle)"
                }
                title += " (Layer: \(window.windowLayer), Size: \(window.frame.size))"
                var item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.representedObject = window
                items.append(item)
            }
            self.selectWindowButton.menu!.items = items
        }
    }
    
    var currentStream: SCStream? {
        willSet {
            if currentStream != nil, currentStream != newValue {
                currentStream?.stopCapture(completionHandler: nil)
            }
        }
    }
    
    var isMain: Bool = true {
        didSet {
            view.superview?.subviews.first { $0.className.contains("TitlebarContainerView") }?.isHidden = !isMain
            selectWindowButton.isHidden = !isMain
            refershButton.isHidden = !isMain
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        print("entered")
    }
    
    override func mouseExited(with event: NSEvent) {
        print("exited")
    }
    
    @IBAction func targetChanged(_ sender: Any) {
        guard let item = selectWindowButton.selectedItem else {
            return
        }
        var filter: SCContentFilter?
        if let window = item.representedObject as? SCWindow {
            filter = .init(desktopIndependentWindow: window)
        } else if let display = item.representedObject as? SCDisplay {
            filter = .init(display: display, excludingWindows: [])
        }
        guard let filter = filter else {
            return
        }
        let streamConfig = SCStreamConfiguration()
        streamConfig.queueDepth = 5
        streamConfig.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfig.showsCursor = false
        let stream = SCStream(filter: filter, configuration: streamConfig, delegate: nil)
        self.currentStream = stream
        try! stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        stream.startCapture(completionHandler: nil)
    }
}

extension ViewController: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        previewView.displayLayer.enqueue(sampleBuffer)
        if let imageBuffer = sampleBuffer.imageBuffer, let window = view.window {
            let width = CVPixelBufferGetWidth(imageBuffer)
            let height = CVPixelBufferGetHeight(imageBuffer)
            let currentRatio = window.aspectRatio.width / window.aspectRatio.height
            let ratio = CGFloat(width) / CGFloat(height)
            if currentRatio.isNaN || abs(currentRatio - ratio) > 0.01 {
                window.aspectRatio = .init(width: width, height: height)
                window.layoutIfNeeded()
            }
        }
    }
}

extension ViewController: NSWindowDelegate {
    func windowDidBecomeMain(_ notification: Notification) {
        isMain = true
    }
    
    func windowDidResignMain(_ notification: Notification) {
        isMain = false
    }
}
