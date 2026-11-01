import Foundation
import AVFoundation
import CoreVideo
import CoreGraphics
import CoreText
import UIKit

/// An independent, on-device route-growth export. Only the scalar snapshot is
/// handed to the encoder; it never reads or mutates the user's live library.
enum NativeReplayMovie {
    struct Point: Sendable {
        let lat: Double; let lon: Double; let time: Double; let gap: Bool
        init(_ point: NativePoint) { lat=point.lat; lon=point.lon; time=point.t; gap=point.isBreak }
    }
    struct RGBA: Sendable {
        let red: Double; let green: Double; let blue: Double; let alpha: Double
        init(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) {
            self.red=red; self.green=green; self.blue=blue; self.alpha=alpha
        }
        @MainActor init(_ color: UIColor) {
            var r: CGFloat=0, g: CGFloat=0, b: CGFloat=0, a: CGFloat=1
            if color.getRed(&r, green:&g, blue:&b, alpha:&a) { self.init(Double(r),Double(g),Double(b),Double(a)) }
            else { self.init(0,0,0) }
        }
        var cgColor: CGColor {
            let components=[red,green,blue,alpha].map { CGFloat($0.isFinite ? min(1,max(0,$0)) : 0) }
            return CGColor(colorSpace:CGColorSpaceCreateDeviceRGB(),components:components)!
        }
    }
    struct Input: Sendable {
        let points: [Point]
        let paper: RGBA
        let ink: RGBA
        let distanceMeters: Double
        let distanceUnit: String
        let title: String
        var dashed = false
    }
    struct Settings: Sendable {
        var width = 720
        var height = 1280
        var framesPerSecond = 24
        var duration = 12.0
        func validate() throws {
            guard (240...1080).contains(width), (240...1920).contains(height), width%2==0, height%2==0,
                  (8...30).contains(framesPerSecond), duration.isFinite, (1...30).contains(duration) else {
                throw NativeError.message("動画の大きさ・長さを確認してください。")
            }
        }
    }
    struct Vertex: Sendable { let x: Double; let y: Double; let time: Double; let gap: Bool }
    struct Geometry: Sendable {
        let vertices: [Vertex]
        let edgeCount: Int
        init(points: [Point]) throws {
            guard points.count<=300_000 else { throw NativeError.message("軌跡が多すぎます。さんぽを 1 件選んで書き出してください。") }
            var segments=[[Point]](), current=[Point]()
            func valid(_ p:Point)->Bool { p.lat.isFinite && p.lon.isFinite && abs(p.lat)<=85 && abs(p.lon)<=180 && p.time.isFinite && abs(p.time)<=8.64e15 }
            for point in points {
                if !valid(point) || point.gap {
                    if current.count>1 { segments.append(current) }; current=[]
                }
                if valid(point) { current.append(point) }
            }
            if current.count>1 { segments.append(current) }
            guard !segments.isEmpty else { throw NativeError.message("動画にできる軌跡がありません。記録点が 2 点以上つながったさんぽを選んでください。") }
            guard segments.count<=8_000 else { throw NativeError.message("区切りが多すぎます。さんぽを 1 件選んで書き出してください。") }
            let sampleStride=max(1,Int(ceil(Double(points.count)/4_000)))
            let world=2 * Double.pi * 6_378_137.0
            var output=[Vertex](), referenceX: Double?
            for segment in segments {
                var previousX: Double?
                for (index, point) in segment.enumerated() where index==0 || index==segment.count-1 || index%sampleStride==0 {
                    var x=6_378_137 * point.lon * .pi/180
                    let anchor=previousX ?? referenceX ?? x
                    // Nearest world copy in constant time, even for imported
                    // routes that accumulate many trips across the antimeridian.
                    x += ((anchor-x)/world).rounded(.toNearestOrAwayFromZero)*world
                    previousX=x; if referenceX==nil { referenceX=x }
                    let y=6_378_137 * log(tan(.pi/4 + point.lat * .pi/360))
                    output.append(Vertex(x:x,y:y,time:point.time,gap:index==0))
                }
            }
            vertices=output
            edgeCount=output.reduce(0) { $0 + ($1.gap ? 0 : 1) }
        }
        func positioned(width:Int,height:Int)->[Vertex] {
            let xs=vertices.map(\.x), ys=vertices.map(\.y)
            let minX=xs.min()!, maxX=xs.max()!, minY=ys.min()!, maxY=ys.max()!
            let padding=Double(width)*0.09
            let rect=CGRect(x:padding,y:Double(height)*0.20,width:Double(width)-2*padding,height:Double(height)*0.58)
            let spanX=max(100,maxX-minX), spanY=max(100,maxY-minY)
            let scale=min(Double(rect.width)/spanX,Double(rect.height)/spanY)
            let midX=(minX+maxX)/2, midY=(minY+maxY)/2
            return vertices.map { Vertex(x:Double(rect.midX)+($0.x-midX)*scale,y:Double(rect.midY)-($0.y-midY)*scale,time:$0.time,gap:$0.gap) }
        }
    }

    static func export(_ input:Input, settings:Settings=Settings(), progress:@escaping @MainActor @Sendable (Double)->Void = {_ in}) async throws -> URL {
        try Task.checkCancellation(); try settings.validate()
        guard input.distanceMeters.isFinite, input.distanceMeters>=0 else { throw NativeError.message("距離を読み取れませんでした。") }
        let geometry=try Geometry(points:input.points)
        let vertices=geometry.positioned(width:settings.width,height:settings.height)
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("PlainWalk-Replay-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var completed=false
        defer { if !completed { try? FileManager.default.removeItem(at:folder) } }
        let url=folder.appendingPathComponent("PlainWalk-map.mp4")
        let writer=try AVAssetWriter(outputURL:url,fileType:.mp4)
        let settingsDictionary:[String:Any]=[
            AVVideoCodecKey:AVVideoCodecType.h264,
            AVVideoWidthKey:settings.width, AVVideoHeightKey:settings.height,
            AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:min(8_000_000,settings.width*settings.height*4),
                AVVideoMaxKeyFrameIntervalKey:settings.framesPerSecond, AVVideoAllowFrameReorderingKey:false]
        ]
        let video=AVAssetWriterInput(mediaType:.video,outputSettings:settingsDictionary)
        video.expectsMediaDataInRealTime=false
        let attributes:[String:Any]=[
            kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String:settings.width, kCVPixelBufferHeightKey as String:settings.height,
            kCVPixelBufferCGImageCompatibilityKey as String:true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String:true,
            kCVPixelBufferIOSurfacePropertiesKey as String:[:]
        ]
        let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:video,sourcePixelBufferAttributes:attributes)
        guard writer.canAdd(video) else { throw NativeError.message("この端末では動画を書き出せません。") }
        writer.add(video)
        guard writer.startWriting() else { throw writer.error ?? NativeError.message("動画の作成を始められませんでした。") }
        writer.startSession(atSourceTime:.zero)
        let count=Int((settings.duration*Double(settings.framesPerSecond)).rounded())
        let deadline=Date().addingTimeInterval(90)
        let date=DateFormatter(); date.locale=Locale(identifier:"ja_JP"); date.calendar=Calendar(identifier:.gregorian); date.dateFormat="yyyy.MM.dd"
        do {
            for index in 0..<count {
                try Task.checkCancellation()
                while !video.isReadyForMoreMediaData {
                    try Task.checkCancellation()
                    guard writer.status == .writing, Date()<deadline else { throw writer.error ?? NativeError.message("動画の書き出しが進みません。もう一度お試しください。") }
                    try await Task.sleep(nanoseconds:10_000_000)
                }
                guard Date()<deadline else { throw NativeError.message("動画の書き出しに時間がかかっています。さんぽを 1 件選んでお試しください。") }
                let amount=count>1 ? min(1,Double(index)/Double(count-1)/0.88) : 1
                let buffer=try autoreleasepool { () throws -> CVPixelBuffer in
                    let pixel=try pixelBuffer(adaptor:adaptor,attributes:attributes,settings:settings)
                    try render(pixel,input:input,vertices:vertices,amount:amount,settings:settings,date:date)
                    return pixel
                }
                guard adaptor.append(buffer,withPresentationTime:CMTime(value:Int64(index),timescale:Int32(settings.framesPerSecond))) else { throw writer.error ?? NativeError.message("動画のフレームを保存できませんでした。") }
                if index%max(1,settings.framesPerSecond/4)==0 || index==count-1 { await progress(Double(index+1)/Double(count)) }
            }
            video.markAsFinished()
            writer.finishWriting {}
            while writer.status == .writing {
                try Task.checkCancellation()
                guard Date()<deadline else { throw NativeError.message("動画の仕上げに時間がかかっています。") }
                try await Task.sleep(nanoseconds:20_000_000)
            }
            guard writer.status == .completed else { throw writer.error ?? NativeError.message("動画の仕上げに失敗しました。") }
            try await validate(url,settings:settings)
            try Task.checkCancellation()
            completed=true
            return url
        } catch { writer.cancelWriting(); throw error }
    }

    /// Only folders created by this exporter can be discarded here.
    static func discard(_ url:URL) {
        let folder=url.deletingLastPathComponent().standardizedFileURL
        guard folder.lastPathComponent.hasPrefix("PlainWalk-Replay-"),
              folder.deletingLastPathComponent().standardizedFileURL == FileManager.default.temporaryDirectory.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at:folder)
    }
    private static func pixelBuffer(adaptor:AVAssetWriterInputPixelBufferAdaptor,attributes:[String:Any],settings:Settings) throws -> CVPixelBuffer {
        var buffer:CVPixelBuffer?
        let status:CVReturn
        if let pool=adaptor.pixelBufferPool { status=CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault,pool,&buffer) }
        else { status=CVPixelBufferCreate(kCFAllocatorDefault,settings.width,settings.height,kCVPixelFormatType_32BGRA,attributes as CFDictionary,&buffer) }
        guard status==kCVReturnSuccess, let buffer else { throw NativeError.message("動画の画像領域を確保できませんでした。") }
        return buffer
    }
    private static func render(_ pixel:CVPixelBuffer,input:Input,vertices:[Vertex],amount:Double,settings:Settings,date:DateFormatter) throws {
        CVPixelBufferLockBaseAddress(pixel,[]); defer { CVPixelBufferUnlockBaseAddress(pixel,[]) }
        guard let memory=CVPixelBufferGetBaseAddress(pixel), let context=CGContext(data:memory,width:settings.width,height:settings.height,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(pixel),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo.byteOrder32Little.rawValue|CGImageAlphaInfo.premultipliedFirst.rawValue) else { throw NativeError.message("動画の画像を描けませんでした。") }
        let width=Double(settings.width), height=Double(settings.height), scale=width/720
        context.translateBy(x:0,y:CGFloat(height)); context.scaleBy(x:1,y:-1)
        context.setFillColor(input.paper.cgColor); context.fill(CGRect(x:0,y:0,width:width,height:height))
        context.setStrokeColor(input.ink.cgColor); context.setLineWidth(CGFloat(max(1.5,4*scale))); context.setLineCap(.round); context.setLineJoin(.round)
        if input.dashed { context.setLineDash(phase:0,lengths:[CGFloat(2*scale),CGFloat(8*scale)]) }
        let visible=min(vertices.count,max(0,Int(Double(vertices.count)*amount)))
        if visible>0 {
            context.beginPath()
            for vertex in vertices.prefix(visible) {
                if vertex.gap { context.move(to:CGPoint(x:vertex.x,y:vertex.y)) }
                else { context.addLine(to:CGPoint(x:vertex.x,y:vertex.y)) }
            }
            context.strokePath()
            let tip=vertices[visible-1]
            context.setFillColor(input.ink.cgColor)
            context.fillEllipse(in:CGRect(x:tip.x-4*scale,y:tip.y-4*scale,width:8*scale,height:8*scale))
        }
        text("PLAINWALK",at:CGPoint(x:44*scale,y:66*scale),size:18*scale,color:input.ink.cgColor,context:context,maxWidth:width-88*scale)
        let title=String(decoding:input.title.utf16.prefix(240),as:UTF16.self).replacingOccurrences(of:"\n",with:" ")
        text(title,at:CGPoint(x:44*scale,y:104*scale),size:26*scale,color:input.ink.cgColor,context:context,maxWidth:width-88*scale)
        if visible>0 { text(date.string(from:Date(timeIntervalSince1970:vertices[visible-1].time/1000)),at:CGPoint(x:44*scale,y:height-128*scale),size:25*scale,color:input.ink.cgColor,context:context,maxWidth:width-88*scale) }
        let distance=String(format:"%.2f",input.distanceMeters/(input.distanceUnit=="mi" ? 1609.344 : 1000))
        text("歩いた距離  "+distance+" "+(input.distanceUnit=="mi" ? "mi" : "km"),at:CGPoint(x:44*scale,y:height-82*scale),size:20*scale,color:input.ink.cgColor,context:context,maxWidth:width-88*scale)
    }
    private static func text(_ value:String,at point:CGPoint,size:Double,color:CGColor,context:CGContext,maxWidth:Double) {
        let attributes:[NSAttributedString.Key:Any]=[
            NSAttributedString.Key(kCTFontAttributeName as String):CTFontCreateWithName("HiraginoSans-W3" as CFString,CGFloat(size),nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):color
        ]
        let line=CTLineCreateWithAttributedString(NSAttributedString(string:value,attributes:attributes) as CFAttributedString)
        let lineWidth=CTLineGetTypographicBounds(line,nil,nil,nil), shrink=min(1,maxWidth/max(1,lineWidth))
        context.saveGState(); context.translateBy(x:point.x,y:point.y); context.scaleBy(x:CGFloat(shrink),y:CGFloat(-shrink)); context.textMatrix = .identity
        CTLineDraw(line,context); context.restoreGState()
    }
    private static func validate(_ url:URL,settings:Settings) async throws {
        let asset=AVURLAsset(url:url)
        guard let track=try await asset.loadTracks(withMediaType:.video).first else { throw NativeError.message("動画に映像がありません。") }
        let size=try await track.load(.naturalSize), duration=try await asset.load(.duration).seconds
        guard Int(size.width)==settings.width, Int(size.height)==settings.height, duration.isFinite,
              abs(duration-settings.duration)<0.3, (try Data(contentsOf:url,options:.mappedIfSafe)).count>0 else { throw NativeError.message("動画の出力を確認できませんでした。") }
    }

    #if DEBUG
    static func selfTest(previewURL:URL? = nil) async throws -> Bool {
        func require(_ condition:Bool,_ message:String) throws { if !condition { throw NativeError.message("Replay movie: "+message) } }
        let raw=[NativePoint(lat:35,lon:139,t:0),NativePoint(lat:35.001,lon:139,t:1000),NativePoint(lat:35.1,lon:139.1,t:2000,isBreak:true),NativePoint(lat:35.101,lon:139.1,t:3000)]
        let points=raw.map(Point.init), geometry=try Geometry(points:points)
        try require(geometry.edgeCount==2 && geometry.vertices.filter(\.gap).count==2,"recording gaps were bridged")
        let crossing=try Geometry(points:[Point(NativePoint(lat:0,lon:179.999,t:0)),Point(NativePoint(lat:0,lon:-179.999,t:1000))])
        try require(crossing.vertices.map(\.x).max()! - crossing.vertices.map(\.x).min()! < 300,"antimeridian took the long way")
        let wraps=(0...72).map { index -> Point in
            let longitude=(Double(index)*120+180).truncatingRemainder(dividingBy:360)-180
            return Point(NativePoint(lat:0,lon:longitude,t:Double(index*1000)))
        }
        let multiwrap=try Geometry(points:wraps)
        let expectedSpan=24*2*Double.pi*6_378_137
        try require(abs((multiwrap.vertices.last!.x-multiwrap.vertices.first!.x)-expectedSpan)<0.01,"multiple world wraps are not stable")
        var shortWalks=[Point]()
        for index in 0..<4_500 {
            shortWalks.append(Point(NativePoint(lat:35+Double(index)*0.000001,lon:139,t:Double(index*2000),isBreak:true)))
            shortWalks.append(Point(NativePoint(lat:35+Double(index)*0.000001,lon:139.00001,t:Double(index*2000+1000))))
        }
        let many=try Geometry(points:shortWalks)
        try require(many.edgeCount==4_500 && many.vertices.count==9_000,"short walks lost an endpoint during sampling")
        let invalid=Point(NativePoint(lat:90,lon:139,t:1500))
        let separated=try Geometry(points:[points[0],points[1],invalid,Point(NativePoint(lat:35.1,lon:139.1,t:2000)),points[3]])
        try require(separated.edgeCount==2,"invalid points invented a connecting edge")
        let input=Input(points:points,paper:RGBA(1,1,1),ink:RGBA(0,0,0),distanceMeters:NativeTrackMath.trailDistance(raw),distanceUnit:"km",title:"Export test")
        let settings=Settings(width:360,height:640,framesPerSecond:8,duration:1)
        let url=try await export(input,settings:settings)
        defer { discard(url) }
        let generator=AVAssetImageGenerator(asset:AVURLAsset(url:url))
        generator.appliesPreferredTrackTransform=true
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let frame=try await generator.image(at:CMTime(value:7,timescale:8))
        try require(frame.image.width==settings.width && frame.image.height==settings.height,"encoded frames cannot be decoded")
        // Cancel this child task after its first encoded frame; the parent
        // smoke task stays live and there is no scheduling-dependent race.
        let task=Task { try await export(input,settings:settings) { _ in
            withUnsafeCurrentTask { $0?.cancel() }
        } }
        var cancelled=false
        do { let unexpected=try await task.value; discard(unexpected) } catch is CancellationError { cancelled=true }
        try require(cancelled,"cancellation did not stop export")
        if let previewURL {
            try FileManager.default.createDirectory(at:previewURL.deletingLastPathComponent(),withIntermediateDirectories:true)
            try Data(contentsOf:url).write(to:previewURL,options:.atomic)
        }
        return true
    }
    #endif
}
