//
//  ViewController.swift
//  WFSignatureView
//
//  Created by babywolf on 17/8/30.
//  Copyright © 2017年 babywolf. All rights reserved.
//

import UIKit
import GLKit

class ViewController: GLKViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        let context = EAGLContext.init(api: EAGLRenderingAPI.openGLES1);
        let view = WFSignatureView.init(frame: self.view.bounds, context: context!);
        view.tag = 1000;
        view.isOpaque = false;
        self.view .addSubview(view);
        
        let space : CGFloat = 30;
        let width = (self.view.frame.width-space*5) / 4;
        
        let btnView = UIView.init(frame: CGRect.init(x: 0, y: self.view.frame.size.height-30, width: self.view.frame.width, height: 25));
        self.view.addSubview(btnView);
        
        for i in 0...3 {
            let btn = UIButton.init(frame: CGRect.init(x: CGFloat(space+(space+width)*CGFloat(i)), y: 0, width: width, height: 25));
            btn.tag = i+100;
            btn.addTarget(self, action: #selector(self.btnAction(sender:)), for: UIControlEvents.touchUpInside);
            switch i {
            case 0:
                btn.backgroundColor=UIColor.black;
            case 1:
                btn.backgroundColor=UIColor.red;
            case 2:
                btn.backgroundColor=UIColor.green;
            case 3:
                btn.backgroundColor=UIColor.blue;
            default:
                btn.backgroundColor=UIColor.black;
            }
            btnView.addSubview(btn);
        }
        
    }
    
    func btnAction(sender : UIButton) {
        let view : WFSignatureView = self.view.viewWithTag(1000) as! WFSignatureView;
        switch sender.tag {
        case 100:
            view.setPenColor(color: UIColor.black);
        case 101:
            view.setPenColor(color: UIColor.red);
        case 102:
            view.setPenColor(color: UIColor.green);
        case 103:
            view.setPenColor(color: UIColor.blue);
        default:
            view.setPenColor(color: UIColor.black);
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

