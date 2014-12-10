//
//  ViewController.swift
//  mailtalkdemo
//
//  Created by anthony on 11/23/14.
//  Copyright (c) 2014 com.anthonyliao. All rights reserved.
//

import UIKit

class ViewController: UIViewController, INModelProviderDelegate {
    @IBOutlet var signinButton: UIButton!
    @IBOutlet var tokenLabel: UILabel!
    var loggedIn: Bool = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func providerDataChanged(provider: INModelProvider!) {
        println("provider data changed")
    }
    
    func provider(provider: INModelProvider!, dataAltered changeSet: INModelProviderChangeSet!) {
        println("provider data change set")
    }
    
    func providerDataFetchCompleted(provider: INModelProvider!) {
        println("provider fetch completed")
    }
    
    func provider(provider: INModelProvider!, dataFetchFailed error: NSError!) {
        println("provider error!")
    }
    
    @IBAction func onSignInClick(sender: UIButton) {
        if !loggedIn {
            println("logging in")
            self.loggedIn = !self.loggedIn
            self.signinButton.setTitle("Sign Out", forState: UIControlState.Normal)
            
            var workBlock: VoidBlock = {() -> Void in
                var namespaces = INAPIManager.shared().namespaces()
                println("namespaces - \(namespaces)")
                var threadProvider = namespaces[0].newThreadProvider()
                println("thread provider - \(threadProvider)")
                threadProvider.itemSortDescriptors = [NSSortDescriptor(key: "lastMessageDate", ascending: false)]
                //                threadProvider.itemFilterPredicate = NSComparisonPredicate(format: "ANY tagIDs = %@", INTag(ID: "inbox"))
//                threadProvider.itemFilterPredicate = NSComparisonPredicate(format: "ANY tagIDs = %@", "sent")
                threadProvider.itemRange = NSMakeRange(0, NSIntegerMax)
                threadProvider.delegate = self
            }
            
            if INAPIManager.shared().isAuthenticated() {
                //check if already authenticated
                println("already authenticated")
                self.tokenLabel.text = INAPIManager.shared().MT.GTMOAuth.accessToken
                workBlock()
            } else {
                //present form
                println("not authenticated, present oauth form")
                
                var presentBlock: ViewControllerBlock = { (oauthViewController: UIViewController!) -> Void in
                    self.presentViewController(oauthViewController, animated: true, completion: nil)
                }
                
                var dismissBlock: ViewControllerBlock = { (oauthViewController: UIViewController!) -> Void in
                    self.dismissViewControllerAnimated(true, completion: nil)
                }
                
                INAPIManager.shared().authenticateWithPresentBlock(presentBlock, andDismissBlock: dismissBlock, andCompletionBlock: { (success: Bool, error: NSError!) -> Void in
                    println("authenticate form block")
                    self.tokenLabel.text = INAPIManager.shared().MT.GTMOAuth.accessToken
                    workBlock()
                })
            }
        } else {
            println("logging out")
            signinButton.setTitle("Sign In", forState: UIControlState.Normal)
            self.tokenLabel.text = "OAuth2 Token"
            loggedIn = !loggedIn
            INAPIManager.shared().unauthenticate()
        }
    }
}

