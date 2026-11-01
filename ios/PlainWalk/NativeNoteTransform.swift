import Foundation

/// Notebook positions are paper coordinates, independent of the on-screen zoom.
/// Snapping tolerances are our implementation, rather than recovered app values.
enum NativeNoteTransform {
    struct State: Equatable {
        var x: Double
        var y: Double
        var width: Double
        var rotation: Double
        var ratio: Double
        init(x: Double, y: Double, width: Double, rotation: Double, ratio: Double = 1) {
            self.x=x;self.y=y;self.width=width;self.rotation=rotation;self.ratio=ratio
        }
        init(_ raw: [String:Any]) {
            x=nativeNumber(raw["x"]) ?? 360;y=nativeNumber(raw["y"]) ?? 480
            width=nativeNumber(raw["width"]) ?? 150;rotation=nativeNumber(raw["rotation"]) ?? 0
            ratio=nativeNumber(raw["ratio"]) ?? 1
        }
        var halfExtent: (x: Double, y: Double) {
            let angle=rotation * .pi / 180, height=width / ratio
            return ((abs(cos(angle))*width+abs(sin(angle))*height)/2,
                    (abs(sin(angle))*width+abs(cos(angle))*height)/2)
        }
    }
    struct Result {
        var state: State
        var guideX: Double?
        var guideY: Double?
        var level: Bool
    }
    /// Recognizer deltas are cumulative only until a recognizer ends. A pan can
    /// outlive a pinch, so restarting that pinch must use the applied pose.
    struct GestureSession {
        private(set) var start: State
        var translation = (x:0.0,y:0.0)
        var magnification = 1.0
        var rotation = 0.0
        init(_ start:State) {self.start=NativeNoteTransform.normalized(start)}
        func result(others:[State]=[],tolerance:Double=8,snap:Bool=true)->Result {
            NativeNoteTransform.transformed(start,translation:translation,scale:magnification,rotation:rotation,others:others,tolerance:tolerance,snap:snap)
        }
        mutating func rebase(to applied:State) {
            start=NativeNoteTransform.normalized(applied)
            translation=(0,0);magnification=1;rotation=0
        }
    }
    static func normalized(_ input: State) -> State {
        func bounded(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            value.isFinite ? min(range.upperBound,max(range.lowerBound,value)) : fallback
        }
        var result=input
        result.x=bounded(input.x,0...720,360);result.y=bounded(input.y,0...960,480)
        result.width=bounded(input.width,10...1000,150);result.ratio=bounded(input.ratio,0.01...100,1)
        let angle=input.rotation.isFinite ? input.rotation.truncatingRemainder(dividingBy:360) : 0
        result.rotation=angle > 180 ? angle-360 : angle < -180 ? angle+360 : angle
        return result
    }
    static func applying(_ state: State, to raw: [String:Any]) -> [String:Any] {
        let state=normalized(state);var next=raw
        next["x"]=state.x;next["y"]=state.y;next["width"]=state.width;next["rotation"]=state.rotation
        return next
    }
    static func transformed(_ start: State, translation: (x:Double,y:Double), scale: Double, rotation: Double,
                            others: [State] = [], tolerance: Double = 8, snap: Bool = true) -> Result {
        var value=normalized(start)
        if translation.x.isFinite {value.x+=translation.x};if translation.y.isFinite {value.y+=translation.y}
        if scale.isFinite && scale>0 {value.width*=scale}
        if rotation.isFinite {value.rotation+=rotation}
        value=normalized(value)
        guard snap else {return Result(state:value,guideX:nil,guideY:nil,level:false)}
        let limit=tolerance.isFinite ? min(30,max(0,tolerance)) : 8
        var level=false
        let horizontal=(value.rotation/180).rounded()*180
        if abs(value.rotation-horizontal)<=4 {value.rotation=horizontal;level=true}
        let extent=value.halfExtent
        var xs=[360.0],ys=[480.0]
        for raw in others {
            let other=normalized(raw), size=other.halfExtent
            xs.append(contentsOf:[other.x-size.x,other.x,other.x+size.x])
            ys.append(contentsOf:[other.y-size.y,other.y,other.y+size.y])
        }
        func adjustment(_ positions:[Double], _ anchors:[Double]) -> (Double,Double)? {
            var best:(Double,Double)?
            for anchor in anchors {
                for position in positions {
                    let delta=anchor-position
                    guard abs(delta)<=limit else {continue}
                    if best==nil || abs(delta)<abs(best!.0) {best=(delta,anchor)}
                }
            }
            return best
        }
        let x=adjustment([value.x,value.x-extent.x,value.x+extent.x],xs)
        let y=adjustment([value.y,value.y-extent.y,value.y+extent.y],ys)
        if let x {value.x+=x.0};if let y {value.y+=y.0}
        value=normalized(value)
        return Result(state:value,guideX:x?.1,guideY:y?.1,level:level)
    }
    static func contains(_ point:(x:Double,y:Double), state raw:State, minimumSize:Double=0) -> Bool {
        let state=normalized(raw), angle = -state.rotation * .pi / 180
        let dx=point.x-state.x,dy=point.y-state.y
        let x=dx*cos(angle)-dy*sin(angle),y=dx*sin(angle)+dy*cos(angle)
        return abs(x)<=max(minimumSize,state.width)/2 && abs(y)<=max(minimumSize,state.width/state.ratio)/2
    }
    #if DEBUG
    static func selfTest() throws -> Bool {
        func check(_ value:Bool,_ message:String)throws {if !value {throw NativeError.message("Notebook transform: "+message)}}
        let raw:[String:Any]=["id":"photo","type":"photo","x":100.0,"y":200.0,"width":200.0,"ratio":2.0,"rotation":0.0,"opacity":0.4,"future":["keep":true]]
        let start=State(raw)
        let first=transformed(start,translation:(30,40),scale:1.5,rotation:17,snap:false).state
        try check(first.x==130 && first.y==240 && first.width==300 && first.rotation==17,"combined deltas")
        // Gesture samples are cumulative from their begin snapshot, not compounded each frame.
        let final=transformed(start,translation:(60,80),scale:2,rotation:34,snap:false).state
        try check(final.x==160 && final.width==400 && final.rotation==34,"cumulative gesture baseline")
        // One finger can keep panning while a second finger lifts, returns,
        // and begins another pinch/rotation. Each recognizer restart is local.
        var session=GestureSession(start)
        session.translation=(20,10);session.magnification=2;session.rotation=15
        let firstPinch=session.result(snap:false).state
        session.rebase(to:firstPinch)
        try check(session.result(snap:false).state==firstPinch,"pinch end cannot reset applied pose")
        session.translation=(10,0)
        let continuedPan=session.result(snap:false).state
        session.rebase(to:continuedPan)
        session.magnification=1.5;session.rotation=10
        let secondPinch=session.result(snap:false).state
        try check(secondPinch.width==600 && secondPinch.x==130 && secondPinch.y==210 && secondPinch.rotation==25,"second pinch and rotation build on continuing pan")
        session.rebase(to:secondPinch)
        session.rotation = -5
        try check(session.result(snap:false).state.rotation==20 && session.result(snap:false).state.width==600,"restarted rotation retains earlier scale")
        let saved=applying(final,to:raw)
        try check(saved["opacity"] as? Double==0.4 && (saved["future"] as? [String:Bool])?["keep"]==true,"unknown fields retained")
        let center=transformed(State(x:355,y:475,width:100,rotation:2),translation:(0,0),scale:1,rotation:0)
        try check(center.state.x==360 && center.state.y==480 && center.state.rotation==0 && center.guideX==360 && center.level,"paper and horizontal snap")
        let other=State(x:100,y:100,width:100,rotation:0)
        let edge=transformed(State(x:204,y:250,width:100,rotation:0),translation:(0,0),scale:1,rotation:0,others:[other])
        try check(edge.state.x==200 && edge.guideX==150,"neighbor edge snap")
        let rotated=State(x:100,y:100,width:200,rotation:90,ratio:2)
        try check(contains((100,190),state:rotated) && !contains((190,100),state:rotated),"rotated hit testing")
        let bounded=transformed(start,translation:(-900,2000),scale:100,rotation:540,snap:false).state
        try check(bounded.x==0 && bounded.y==960 && bounded.width==1000 && bounded.rotation==180,"bounds and angle wrapping")
        let finite=transformed(start,translation:(.nan,.infinity),scale:.nan,rotation:.nan,snap:false).state
        try check(finite==start,"invalid deltas leave valid draft intact")
        try check(normalized(State(x:.nan,y:.infinity,width:-1,rotation:.nan,ratio:0)).ratio==0.01,"invalid imported bounds")
        return true
    }
    #endif
}
