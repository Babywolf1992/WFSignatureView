//
//  WFSignatureView.swift
//  WFSignatureView
//
//  Created by babywolf on 17/8/30.
//  Copyright © 2017年 babywolf. All rights reserved.
//

import UIKit
import GLKit
import OpenGLES.ES2.glext

let STROKE_WIDTH_MIN = 0.004 // Stroke width determined by touch velocity
let STROKE_WIDTH_MAX = 0.030
let STROKE_WIDTH_SMOOTHING = 0.5   // Low pass filter alpha

let VELOCITY_CLAMP_MIN = 20
let VELOCITY_CLAMP_MAX = 5000

let QUADRATIC_DISTANCE_TOLERANCE = 3.0   // Minimum distance to make a curve

let MAXIMUM_VERTECES = 100000

let StrokeColor : GLKVector3 = GLKVector3.init(v: (0, 0, 0))
var clearColor : Array<CGFloat> = [1.0,1.0,1.0,0.0]

public struct _WFSignaturePoint {
    public var vertex : GLKVector3
    public var color : GLKVector3
}
public typealias WFSignaturePoint = _WFSignaturePoint

let maxLength = MAXIMUM_VERTECES

func addVertex( length : inout uint, v : UnsafeRawPointer) {
    if Int(length) >= maxLength {
        return;
    }
    var data : UnsafeMutableRawPointer
    data = glMapBufferOES(UInt32(GL_ARRAY_BUFFER), UInt32(GL_WRITE_ONLY_OES))
    data = data + MemoryLayout<WFSignaturePoint>.size * Int(length)
    memcpy(data, v, MemoryLayout<WFSignaturePoint>.size)
    glUnmapBufferOES(GLenum(GL_ARRAY_BUFFER));
    length += 1
}

func QuadraticPointInCurve( start : CGPoint, end : CGPoint, controlPoint : CGPoint, percent : Float) -> CGPoint {
    var a, b, c : Float
    a = pow((1.0-percent), 2.0);
    b = 2.0 * percent * (1.0 - percent);
    c = pow(percent, 2.0);
    
    return CGPoint.init(x: Double(a) * Double(start.x) + Double(b) * Double(controlPoint.x) + Double(c) * Double(end.x), y: Double(a) * Double(start.y) + Double(b) * Double(controlPoint.y) + Double(c) * Double(end.y));
}

func generateRandom(from : Float, to : Float) -> Float {
    return Float(arc4random() % 10000) / 10000.0 * (to - from) + from;
}

func clamp(min : Float, max : Float, value : Float) -> Float {
    return fmaxf(min, fminf(max, value));
}

func perpendicular(p1 : WFSignaturePoint, p2 : WFSignaturePoint) -> GLKVector3 {
    let ret = GLKVector3.init(v: (p2.vertex.y - p1.vertex.y, -1 * (p2.vertex.x - p1.vertex.x), 0))
    return ret;
}

func viewPointToGL(viewPoint : CGPoint, bounds : CGRect, color : GLKVector3) -> WFSignaturePoint {
    return WFSignaturePoint.init(vertex: GLKVector3.init(v: (Float(viewPoint.x / bounds.size.width * 2.0) - 1, (Float((viewPoint.y / bounds.size.height) * 2.0) - 1) * -1, 0)), color: color);
}

class WFSignatureView: GLKView {
    var strokeColor : UIColor?;
    
    var hasSignature : Bool;
    
    var signatureImage : UIImage? {
        get {
            return self.snapshot;
        }
    }
    
    // OpenGL state
    var glContext : EAGLContext?
    var effect : GLKBaseEffect?
    
    var vertexArray : GLuint = 0
    var vertexBuffer : GLuint = 0
    var dotsArray : GLuint = 0
    var dotsBuffer : GLuint = 0
    
    var signatureVertexData : Array<WFSignaturePoint?> = Array.init(repeating: nil, count: maxLength)
    var length : uint = 0
    
    var signatureDotsData : Array<WFSignaturePoint?> = Array.init(repeating: nil, count: maxLength)
    var dotsLength : uint = 0
    
    var penThickness : Float = 0.0;
    var previousThickness : Float = 0.0;
    
    var previousPoint : CGPoint?
    var previousMidPoint : CGPoint?
    var previousVertex : WFSignaturePoint?
    var currentVelocity : WFSignaturePoint?
    
    required init?(coder aDecoder: NSCoder) {
        self.hasSignature = true;
        super.init(coder: aDecoder);
        self.commonInit();
    }
    
    override init(frame: CGRect, context: EAGLContext) {
        self.hasSignature = true;
        super.init(frame: frame, context: context);
        self.commonInit();
    }
    
    func commonInit() {
        glContext = EAGLContext.init(api: EAGLRenderingAPI(rawValue: 2)!)
        if glContext != nil {
            time(UnsafeMutablePointer.init(bitPattern: 0));
            
            self.backgroundColor = UIColor.white;
            self.setBackgroundColor(backgroundColor: UIColor.white);
            self.isOpaque = false;
            
            self.context = glContext!;
            self.drawableDepthFormat = GLKViewDrawableDepthFormat.init(rawValue: 2)!;
            self.enableSetNeedsDisplay = true;
            
            self.drawableMultisample = GLKViewDrawableMultisample.init(rawValue: 1)!;
            
            self.setupGL();
            
            let pan = UIPanGestureRecognizer.init(target: self, action: #selector(self.pan(p:)));
            pan.maximumNumberOfTouches = 1;
            pan.minimumNumberOfTouches = 1;
            pan.cancelsTouchesInView = true;
            self.addGestureRecognizer(pan);
            
            let tap = UITapGestureRecognizer.init(target: self, action: #selector(self.tap(t:)));
            tap.cancelsTouchesInView = true;
            self.addGestureRecognizer(tap);
            
            let longer = UILongPressGestureRecognizer.init(target: self, action: #selector(self.longPress(p:)));
            longer.cancelsTouchesInView = true;
            self.addGestureRecognizer(longer);
        }else {
            print("NSOpenGLES2ContextException");
        }
    }
    
    deinit {
        self.tearDownGL();
        
        if EAGLContext.current() == glContext {
            EAGLContext.setCurrent(nil);
        }
        glContext = nil;
    }
    
    override func draw(_ rect: CGRect) {
        glClearColor(GLfloat(clearColor[0]), GLfloat(clearColor[1]), GLfloat(clearColor[2]), GLfloat(clearColor[3]))
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT));
        
        effect?.prepareToDraw();
        
        if length > 2 {
            glBindVertexArrayOES(vertexArray);
            glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, GLsizei(length));
        }
        
        if dotsLength > 0 {
            glBindVertexArrayOES(dotsArray);
            glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, GLsizei(dotsLength));
        }
    }
    
    func erase() {
        length = 0;
        dotsLength = 0;
        self.hasSignature = false;
        
        self.setNeedsDisplay();
    }
    
    static var segments : Int = 20;
    func tap(t : UITapGestureRecognizer) {
        let l = t.location(in: self);
        
        if t.state == UIGestureRecognizerState.recognized {
            glBindBuffer(GLenum(GL_ARRAY_BUFFER), dotsBuffer);
            
            var touchPoint : WFSignaturePoint = viewPointToGL(viewPoint: l, bounds: self.bounds, color: GLKVector3.init(v: (1, 1, 1)));
            addVertex(length: &dotsLength, v: &touchPoint);
            
            var centerPoint = touchPoint;
            centerPoint.color = StrokeColor;
            addVertex(length: &dotsLength, v: &centerPoint);
            
            let radius = GLKVector2.init(v: (clamp(min: 0.00001, max: 0.02, value: penThickness * generateRandom(from: 0.5, to: 1.5)), clamp(min: 0.00001, max: 0.02, value: penThickness * generateRandom(from: 0.5, to: 1.5))));
            let velocityRadius = radius;
            var angle : Float = 0.0;
            
            for _ in 0 ... WFSignatureView.segments {
                let p = centerPoint;
                let x = p.vertex.x + velocityRadius.x * cosf(angle);
                let y = p.vertex.y + velocityRadius.y * sinf(angle);
                var point : WFSignaturePoint = WFSignaturePoint.init(vertex: GLKVector3.init(v: (x, y, p.vertex.z)), color: p.color);
                addVertex(length: &dotsLength, v: &point);
                addVertex(length: &dotsLength, v: &centerPoint);
                
                angle += Float(M_PI * 2.0 / Double(WFSignatureView.segments));
            }
            
            addVertex(length: &dotsLength, v: &touchPoint);
            glBindBuffer(GLenum(GL_ARRAY_BUFFER), 0);
        }
        self.setNeedsDisplay();
    }
    
    func longPress(p : UILongPressGestureRecognizer) {
        self.erase();
    }
    
    func pan(p : UIPanGestureRecognizer) {
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vertexBuffer);
        
        let v : CGPoint = p.velocity(in: self);
        let l : CGPoint = p.location(in: self);
        
        currentVelocity = viewPointToGL(viewPoint: v, bounds: self.bounds, color: GLKVector3.init(v: (0, 0, 0)));
        
        var distance : Float = 0.0
        if previousPoint!.x > 0 {
            let a1 = (l.x - previousPoint!.x) * (l.x - previousPoint!.x);
            let a = a1 + (l.y - previousPoint!.y) * (l.y - previousPoint!.y);
            distance = sqrtf(Float(a));
        }
        
        let velocityMagnitude = sqrtf(Float(v.x * v.x + v.y * v.y));
        let clampedVelocityMagnitude = clamp(min: Float(VELOCITY_CLAMP_MIN), max: Float(VELOCITY_CLAMP_MAX), value: velocityMagnitude);
        let normalizedVelocity = (clampedVelocityMagnitude - Float(VELOCITY_CLAMP_MIN)) / Float(VELOCITY_CLAMP_MAX - VELOCITY_CLAMP_MIN);
        
        let lowPassFilterAlpha = STROKE_WIDTH_SMOOTHING;
        let newThickness = Float(STROKE_WIDTH_MAX - STROKE_WIDTH_MIN) * Float(1 - normalizedVelocity) + Float(STROKE_WIDTH_MIN);
        penThickness = penThickness * Float(lowPassFilterAlpha) + newThickness * Float(1 - lowPassFilterAlpha);
        if p.state == UIGestureRecognizerState.began {
            previousPoint = l;
            previousMidPoint = l;
            
            var startPoint = viewPointToGL(viewPoint: l, bounds: self.bounds, color: GLKVector3.init(v: (1, 1, 1)));
            previousVertex = startPoint;
            previousThickness = penThickness;
            
            addVertex(length: &length, v: &startPoint);
            addVertex(length: &length, v: &previousVertex!);
            
            self.hasSignature = true;
        }else if p.state == UIGestureRecognizerState.changed {
            let mid = CGPoint.init(x: (l.x + (previousPoint?.x)!) / 2.0, y: (l.y + (previousPoint?.y)!) / 2.0);
            if distance > Float(QUADRATIC_DISTANCE_TOLERANCE) {
                let segmts : Int = Int(distance/1.5);
                let startPenThickness = previousThickness;
                let endPenThickness = penThickness;
                previousThickness = penThickness;
                
                for index in 0 ... (segmts-1) {
                    penThickness = startPenThickness + ((endPenThickness - startPenThickness) / Float(segmts)) * Float(index);
                    let quadPoint = QuadraticPointInCurve(start: previousMidPoint!, end: mid, controlPoint: previousPoint!, percent: Float(index)/Float(segmts));
                    let wfv = viewPointToGL(viewPoint: quadPoint, bounds: self.bounds, color: StrokeColor);
                    self.addTriangleStripPointsForPrevious(previous: previousVertex!, next: wfv)
                    previousVertex = wfv;
                }
            } else if distance > 1.0 {
                let wfv = viewPointToGL(viewPoint: l, bounds: self.bounds, color: StrokeColor);
                self.addTriangleStripPointsForPrevious(previous: previousVertex!, next: wfv);
                previousVertex = wfv;
                previousThickness = penThickness;
            }
            previousPoint = l;
            previousMidPoint = mid;
        } else if p.state == UIGestureRecognizerState.ended || p.state == UIGestureRecognizerState.cancelled {
            var wfv = viewPointToGL(viewPoint: l, bounds: self.bounds, color: GLKVector3.init(v: (1, 1, 1)));
            addVertex(length: &length, v: &wfv);
            previousVertex = wfv;
            addVertex(length: &length, v: &previousVertex!);
        }
        self.setNeedsDisplay();
    }
    
    func setStrokeColor(strokeColor : UIColor) {
        self.strokeColor = strokeColor;
        self.updateStrokeColor();
    }
    
    func updateStrokeColor() {
        var red : CGFloat = 0, green : CGFloat = 0, blue : CGFloat = 0, alpha : CGFloat = 0, white : CGFloat = 1;
        if (effect != nil) && (self.strokeColor != nil) && self.strokeColor!.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            effect?.constantColor = GLKVector4.init(v: (Float(red), Float(green), Float(blue), Float(alpha)));
        }else if effect != nil && self.strokeColor != nil && self.strokeColor!.getWhite(&white, alpha: &alpha) {
            effect?.constantColor = GLKVector4.init(v: (Float(white), Float(white), Float(white), Float(alpha)));
        }else {
            effect?.constantColor = GLKVector4.init(v: (0, 0, 0, 1));
        }
    }
    
    func setBackgroundColor(backgroundColor : UIColor) {
        self.backgroundColor = backgroundColor;
        
        var red : CGFloat = 0, green : CGFloat = 0, blue : CGFloat = 0, alpha : CGFloat = 0, white : CGFloat = 1;
        if backgroundColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            clearColor[0] = red;
            clearColor[1] = green;
            clearColor[2] = blue;
        }else if backgroundColor.getWhite(&white, alpha: &alpha) {
            clearColor[0] = white;
            clearColor[1] = white;
            clearColor[2] = white;
        }
    }
    
    func bindShaderAttributes() {
        glEnableVertexAttribArray(GLuint(GLKVertexAttrib.position.rawValue));
        glVertexAttribPointer(GLuint(GLKVertexAttrib.position.rawValue), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(MemoryLayout<WFSignaturePoint>.size), nil);
    }
    
    func setupGL() {
        EAGLContext.setCurrent(glContext);
        effect = GLKBaseEffect.init();
        self.updateStrokeColor();
        glDisable(GLenum(GL_DEPTH_TEST));
        
        glGenVertexArraysOES(1, &vertexArray);
        glBindVertexArrayOES(vertexArray);
        
        glGenBuffers(1, &vertexBuffer);
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vertexBuffer);
        glBufferData(GLenum(GL_ARRAY_BUFFER), MemoryLayout<WFSignaturePoint>.size * maxLength, signatureVertexData, GLenum(GL_DYNAMIC_DRAW));
        self.bindShaderAttributes();
        
        glGenVertexArraysOES(1, &dotsArray);
        glBindVertexArrayOES(dotsArray);
        
        glGenBuffers(1, &dotsBuffer);
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), dotsBuffer);
        glBufferData(GLenum(GL_ARRAY_BUFFER), MemoryLayout<WFSignaturePoint>.size * maxLength, signatureDotsData, GLenum(GL_DYNAMIC_DRAW));
        self.bindShaderAttributes();
        
        glBindVertexArrayOES(0);
        
        let ortho : GLKMatrix4 = GLKMatrix4MakeOrtho(-1, 1, -1, 1, 0.1, 2.0);
        effect?.transform.projectionMatrix = ortho;
        
        let modelViewMatrix : GLKMatrix4 = GLKMatrix4MakeTranslation(0.0, 0.0, -1.0);
        effect?.transform.modelviewMatrix = modelViewMatrix;
        
        length = 0;
        penThickness = 0.003;
        previousPoint = CGPoint.init(x: -100, y: -100);
    }
    
    func addTriangleStripPointsForPrevious(previous : WFSignaturePoint, next : WFSignaturePoint) {
        var toTravel = penThickness / 2.0;
        for _ in 0 ... 1 {
            let p = perpendicular(p1: previous, p2: next);
            let p1 = next.vertex;
            let ref = GLKVector3Add(p1, p);
            
            let distance = GLKVector3Distance(p1, ref);
            var difX = p1.x - ref.x;
            var difY = p1.y - ref.y;
            let ratio = -1.0 * (toTravel / distance);
            
            difX = difX * ratio;
            difY = difY * ratio;
            
            var stripPoint = WFSignaturePoint.init(vertex: GLKVector3.init(v: (p1.x + difX, p1.y + difY, 0.0)), color: StrokeColor);
            addVertex(length: &length, v: &stripPoint);
            toTravel *= -1;
        }
    }
    
    func tearDownGL() {
        EAGLContext.setCurrent(glContext);
        glDeleteVertexArraysOES(1, &vertexArray);
        glDeleteBuffers(1, &vertexBuffer);
        
        glDeleteVertexArraysOES(1, &dotsArray);
        glDeleteBuffers(1, &dotsBuffer);
    }
}
