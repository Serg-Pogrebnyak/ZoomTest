//
//  ViewController.swift
//  ZoomTest
//
//  Created by Sergey Pohrebnuak on 10/2/19.
//  Copyright © 2019 Sergey Pohrebnuak. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    
    fileprivate let zoomService = ZoomServiceNew()

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    @IBAction func didTapStartButton(_ sender: Any) {
        zoomService.startIdentityMatching(vc: self) { (success, desc, matchLevelOptional) in
            print(success, desc, matchLevelOptional)
        }
    }
    
}

