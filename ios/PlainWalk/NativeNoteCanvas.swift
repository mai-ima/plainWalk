import SwiftUI
import UIKit

/// The static notebook remains the export renderer. Only this editing surface
/// adds selection/guide drawing and native UIKit simultaneous recognizers.
struct NativeNoteCanvas<Content:View>: View {
    @Binding var layout:[[String:Any]]
    @Binding var selectedID:String?
    let onBegin:()->Void
    let content:()->Content
    init(layout:Binding<[[String:Any]]>,selectedID:Binding<String?>,onBegin:@escaping()->Void,@ViewBuilder content:@escaping()->Content) {
        self._layout=layout;self._selectedID=selectedID;self.onBegin=onBegin;self.content=content
    }
    var body:some View {
        content().overlay {
            NativeNoteGestureSurface(layout:$layout,selectedID:$selectedID,onBegin:onBegin)
                .accessibilityHidden(true)
        }.clipped()
    }
}

private struct NativeNoteGestureSurface:UIViewRepresentable {
    @Binding var layout:[[String:Any]]
    @Binding var selectedID:String?
    let onBegin:()->Void
    func makeCoordinator()->Coordinator {Coordinator(self)}
    func makeUIView(context:Context)->Surface {
        let view=Surface();view.backgroundColor = .clear;view.isOpaque=false
        context.coordinator.view=view;view.owner=context.coordinator
        let tap=UITapGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.tap(_:)))
        let pan=UIPanGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.pan(_:)))
        let pinch=UIPinchGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.pinch(_:)))
        let rotate=UIRotationGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.rotate(_:)))
        for recognizer in [tap,pan,pinch,rotate] {recognizer.delegate=context.coordinator;view.addGestureRecognizer(recognizer)}
        tap.require(toFail:pan)
        return view
    }
    func updateUIView(_ view:Surface,context:Context) {context.coordinator.parent=self;view.setNeedsDisplay()}
    static func dismantleUIView(_ view:Surface,coordinator:Coordinator) {view.owner=nil;coordinator.view=nil}
    final class Surface:UIView {
        weak var owner:Coordinator?
        override func point(inside point:CGPoint,with event:UIEvent?)->Bool {owner?.hit(point) != nil}
        override func draw(_ rect:CGRect) {owner?.draw()}
    }
    final class Coordinator:NSObject,UIGestureRecognizerDelegate {
        var parent:NativeNoteGestureSurface
        weak var view:Surface?
        private var active=Set<ObjectIdentifier>()
        private var editingID:String?
        private var start:NativeNoteTransform.State?
        private var dx=0.0,dy=0.0,magnification=1.0,angle=0.0
        private var guideX:Double?,guideY:Double?
        private var snapped=false
        private var remembered=false
        init(_ parent:NativeNoteGestureSurface){self.parent=parent}
        private var scale:Double {max(0.001,Double(view?.bounds.width ?? 0)/720)}
        func hit(_ location:CGPoint)->String? {
            let point=(x:Double(location.x)/scale,y:Double(location.y)/scale)
            return parent.layout.reversed().first {raw in
                raw["id"] is String && NativeNoteTransform.contains(point,state:.init(raw),minimumSize:36/scale)
            }?["id"] as? String
        }
        func gestureRecognizerShouldBegin(_ recognizer:UIGestureRecognizer)->Bool {
            guard let view else{return false}
            if let editingID {return parent.layout.contains {$0["id"] as? String==editingID}}
            return hit(recognizer.location(in:view)) != nil
        }
        func gestureRecognizer(_ gestureRecognizer:UIGestureRecognizer,shouldRecognizeSimultaneouslyWith other:UIGestureRecognizer)->Bool {
            guard let view else{return false}
            return gestureRecognizer.view===view && other.view===view && !(gestureRecognizer is UITapGestureRecognizer) && !(other is UITapGestureRecognizer)
        }
        func gestureRecognizer(_ gestureRecognizer:UIGestureRecognizer,shouldBeRequiredToFailBy other:UIGestureRecognizer)->Bool {
            guard let view,let ancestor=other.view,ancestor !== view else{return false}
            // Dragging an item edits it; blank paper still scrolls the editor.
            // Our recognizers immediately fail when their first touch misses an item.
            return gestureRecognizer.view===view && !(gestureRecognizer is UITapGestureRecognizer) && view.isDescendant(of:ancestor)
        }
        @objc func tap(_ recognizer:UITapGestureRecognizer) {
            guard let view,recognizer.state == .ended else{return}
            parent.selectedID=hit(recognizer.location(in:view));view.setNeedsDisplay()
        }
        private func begin(_ recognizer:UIGestureRecognizer)->Bool {
            if start==nil {
                guard let view,let id=hit(recognizer.location(in:view)),let raw=parent.layout.first(where:{$0["id"] as? String==id}) else{return false}
                editingID=id;parent.selectedID=id;start = .init(raw)
                dx=0;dy=0;magnification=1;angle=0;snapped=false;remembered=false
            }
            active.insert(ObjectIdentifier(recognizer));return true
        }
        private func apply() {
            guard let start,let id=editingID,let index=parent.layout.firstIndex(where:{$0["id"] as? String==id}) else{return}
            let others=parent.layout.filter{$0["id"] as? String != id}.map(NativeNoteTransform.State.init)
            let result=NativeNoteTransform.transformed(start,translation:(dx,dy),scale:magnification,rotation:angle,others:others,tolerance:6/scale)
            guideX=result.guideX;guideY=result.guideY
            let nowSnapped=guideX != nil || guideY != nil
            if nowSnapped && !snapped {UISelectionFeedbackGenerator().selectionChanged()};snapped=nowSnapped
            if !remembered && result.state != NativeNoteTransform.normalized(start) {parent.onBegin();remembered=true}
            parent.layout[index]=NativeNoteTransform.applying(result.state,to:parent.layout[index])
            view?.setNeedsDisplay()
        }
        private func end(_ recognizer:UIGestureRecognizer) {
            active.remove(ObjectIdentifier(recognizer))
            if active.isEmpty {start=nil;editingID=nil;guideX=nil;guideY=nil;view?.setNeedsDisplay()}
        }
        @objc func pan(_ recognizer:UIPanGestureRecognizer) {
            if recognizer.state == .began && !begin(recognizer) {return}
            guard start != nil else{return}
            let value=recognizer.translation(in:view);dx=Double(value.x)/scale;dy=Double(value.y)/scale;apply()
            if [.ended,.cancelled,.failed].contains(recognizer.state){end(recognizer)}
        }
        @objc func pinch(_ recognizer:UIPinchGestureRecognizer) {
            if recognizer.state == .began && !begin(recognizer) {return}
            guard start != nil else{return}
            magnification=Double(recognizer.scale);apply()
            if [.ended,.cancelled,.failed].contains(recognizer.state){end(recognizer)}
        }
        @objc func rotate(_ recognizer:UIRotationGestureRecognizer) {
            if recognizer.state == .began && !begin(recognizer) {return}
            guard start != nil else{return}
            angle=Double(recognizer.rotation)*180 / .pi;apply()
            if [.ended,.cancelled,.failed].contains(recognizer.state){end(recognizer)}
        }
        func draw() {
            guard let view,let context=UIGraphicsGetCurrentContext(),let id=parent.selectedID,
                  let raw=parent.layout.first(where:{$0["id"] as? String==id}) else{return}
            let state=NativeNoteTransform.normalized(.init(raw)),factor=CGFloat(scale)
            context.saveGState();context.setStrokeColor(UIColor.systemBlue.cgColor);context.setLineWidth(1)
            if let guideX {context.move(to:.init(x:CGFloat(guideX)*factor,y:0));context.addLine(to:.init(x:CGFloat(guideX)*factor,y:view.bounds.height));context.strokePath()}
            if let guideY {context.move(to:.init(x:0,y:CGFloat(guideY)*factor));context.addLine(to:.init(x:view.bounds.width,y:CGFloat(guideY)*factor));context.strokePath()}
            context.translateBy(x:CGFloat(state.x)*factor,y:CGFloat(state.y)*factor)
            context.rotate(by:CGFloat(state.rotation * .pi / 180))
            let width=CGFloat(state.width)*factor,height=CGFloat(state.width/state.ratio)*factor
            let bounds=CGRect(x:-width/2,y:-height/2,width:width,height:height)
            context.setLineDash(phase:0,lengths:[4,3]);context.stroke(bounds.insetBy(dx:-3,dy:-3))
            context.setLineDash(phase:0,lengths:[]);context.setFillColor(UIColor.systemBlue.cgColor)
            for x in [bounds.minX,bounds.maxX] {for y in [bounds.minY,bounds.maxY] {context.fillEllipse(in:CGRect(x:x-3,y:y-3,width:6,height:6))}}
            context.restoreGState()
        }
    }
}
