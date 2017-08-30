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
        view.isOpaque = false;
        self.view .addSubview(view);
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

