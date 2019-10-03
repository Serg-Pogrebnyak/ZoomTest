//
//  ZoomService.swift
//  ZoomTest
//
//  Created by Sergey Pohrebnuak on 10/2/19.
//  Copyright © 2019 Sergey Pohrebnuak. All rights reserved.
//

import Foundation
import ZoomAuthentication

class ZoomServiceNew: NSObject, ZoomManagedSessionDelegate,  URLSessionDelegate {

    private let enrolmentId = "ios_complete_app_" + UUID().uuidString
    private let zoomServerBaseURL = "https://api.zoomauth.com/api/v2/biometrics"
    private let licenseKeyIdentifier = "d0lRA0dhpYtBJaMu8wqiQ5LHSNXvmAOF"
    private var zoomManagedSession: ZoomManagedSession!
    private var activeAPITask: URLSessionTask!
    private var compleation: ((Bool, String, Int?) -> Void)?
    private var success: Bool?
    private var desc: String?

    override init() {
        super.init()
        Zoom.sdk.initialize(licenseKeyIdentifier: licenseKeyIdentifier, completion: nil)
        self.deleteUserEnrollment()
    }

    func isZoomRedyToStart() -> Bool {
        return Zoom.sdk.getStatus() == .initialized
    }

    func startIdentityMatching(vc: UIViewController, compleation: @escaping(Bool, String, Int?) -> Void) {
        deleteUserEnrollment()
        self.compleation = compleation

        Zoom.sdk.setCustomization(ZoomCustomization())
        zoomManagedSession = ZoomManagedSession(delegate: self, fromVC: vc, licenseKey: self.licenseKeyIdentifier, zoomServerBaseURL: self.zoomServerBaseURL, mode: ZoomManagedSessionMode.enroll, enrollmentIdentifier: enrolmentId)
    }

    func onZoomManagedSessionComplete(status: ZoomManagedSessionStatus) {
        self.desc = getZoomStatusesDescription(zoomManagedSessionStatus: status)
        self.success = status == .success
        if self.success! {
            matchUser3dWith2d()
        } else {
            compleation?(success!, desc!, nil)
        }
    }

    private func getZoomStatusesDescription(zoomManagedSessionStatus: ZoomManagedSessionStatus) -> String {
        if zoomManagedSessionStatus == .unsuccessCheckSubcode {
            if zoomManagedSession?.latestZoomSessionResult != nil && zoomManagedSession.latestZoomSessionResult?.status != .sessionCompletedSuccessfully {
                return(Zoom.sdk.description(for: zoomManagedSession.latestZoomSessionResult!.status))
            }
            else {
                return(Zoom.sdk.description(for: zoomManagedSession.latestZoomManagedSessionStatusSubCode))
            }
        }
        else {
            return(Zoom.sdk.description(for: zoomManagedSessionStatus))
        }
    }

    //MARK: - passport check from base64
    func matchUser3dWith2d() {

        var parameters: [String : Any] = [:]
        var target: [String : Any] = [:]
        var source: [String : Any] = [:]
        source["enrollmentIdentifier"] = enrolmentId
        target["image"] = imageInBase64
        let sessionId = UUID().uuidString
        parameters["source"] = source
        parameters["target"] = target
        parameters["sessionId"] = sessionId

        let request = buildHTTPRequest(method: "POST", endpoint: "/match-3d-2d", parameters: parameters)
        let session = URLSession(configuration: URLSessionConfiguration.default, delegate: self, delegateQueue: OperationQueue.main)

        if self.activeAPITask != nil && self.activeAPITask.state != .completed {
            self.activeAPITask.cancel()
        }

        self.activeAPITask = session.dataTask(with: request as URLRequest, completionHandler: { responseData, response, error in

            guard let responseData = responseData, error == nil else {
                self.compleation?(self.success!, self.desc!, nil)
                return
            }

            do {
                let json = try JSONSerialization.jsonObject(with: responseData, options: JSONSerialization.ReadingOptions.allowFragments) as! [String : AnyObject]
                print(json)
                if let matchLevel = json["data"]?["matchLevel"] as? Int {
                    self.compleation?(self.success!, self.desc!, matchLevel)
                } else {
                    self.compleation?(self.success!, self.desc!, nil)
                }
            }
            catch {
                self.compleation?(self.success!, self.desc!, nil)
            }
        })

        self.activeAPITask.resume()
    }

    //MARK: - delete user and url configurator
    private func deleteUserEnrollment() {
        let endpoint: String = "/enrollment/\(enrolmentId)"
        var parameters: [String : Any] = [:]
        parameters["enrollmentIdentifier"] = enrolmentId
        let request: NSMutableURLRequest = buildHTTPRequest(method: "DELETE", endpoint: endpoint, parameters: parameters)
        let session: URLSession = URLSession(configuration: URLSessionConfiguration.default, delegate: self, delegateQueue: OperationQueue.main)

        if self.activeAPITask != nil && self.activeAPITask.state != .completed {
            self.activeAPITask.cancel()
        }
        self.activeAPITask = session.dataTask(with: request as URLRequest, completionHandler: { responseData, response, error in

            guard let responseData = responseData , error == nil else {
                return
            }

            do {
                let json = try JSONSerialization.jsonObject(with: responseData, options: JSONSerialization.ReadingOptions.allowFragments) as! [String : AnyObject]
                print(json["meta"]!["message"] as! String)
            }
            catch {
                print("Exception caught while handling response from FaceTec API: \(error.localizedDescription)")
            }
        })

        self.activeAPITask.resume()
    }

    private func buildHTTPRequest(method: String, endpoint: String, parameters: [String : Any]) -> NSMutableURLRequest {
        let request = NSMutableURLRequest(url: NSURL(string: self.zoomServerBaseURL + endpoint)! as URL)
        request.httpMethod = method
        // Only send data if there are parameters and this is not a GET request
        if parameters.count > 0 && method != "GET" {
            request.httpBody = try! JSONSerialization.data(withJSONObject: parameters as Any, options: JSONSerialization.WritingOptions(rawValue: 0))
        }
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(self.licenseKeyIdentifier, forHTTPHeaderField: "X-Device-License-Key")
        let sessionId: String = parameters["sessionId"] as? String ?? "nil"

        request.addValue(Zoom.sdk.createZoomAPIUserAgentString(sessionId),
                         forHTTPHeaderField: "User-Agent")

        return request
    }
    
    private let imageInBase64 = "/9j/4AAQSkZJRgABAQAASABIAAD/4QBYRXhpZgAATU0AKgAAAAgAAgESAAMAAAABAAEAAIdpAAQAAAABAAAAJgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAyKADAAQAAAABAAAA+gAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgA+gDIAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/bAEMABgYGBgYGCgYGCg4KCgoOEg4ODg4SFxISEhISFxwXFxcXFxccHBwcHBwcHCIiIiIiIicnJycnLCwsLCwsLCwsLP/bAEMBBwcHCwoLEwoKEy4fGh8uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLv/dAAQADf/aAAwDAQACEQMRAD8A+gqKBS0AJimmnGmmgBtNJp/WmlaAHLzUhx6VEvFNeQhsCgBSVLbcCqU95BbybJGC/Wq+o30enxedIwDdQD3rx7XvED31wXU4znpQB7XHd28/+rcH6VaXA61494Z1JItvnSY+pr1aG8guhmJw30oA0NynsKDiqudj7KnJxQA6kpm+l3ZoAdSUZooASkNONJQAlFFFABRRRQAClxQKdigD/9D6CFKKTFOoAaajJqU1GVzQAq04ihFpsrlOgoAF27tpNZmqaha2CMxkG4dqx9W1tbAM+RuHavE9f8Q3Gp3Zc5AOelAG94r8QvqroFOBGpXjjPNcCGI6mmmQ9zmmFs0AT+fIv3CR9DXUaJ4j1PTypVwUHYjJ/OuSFTK2KAPovRdbg1aIXErhZD/DXRsQelfLdjrFxp96siZIHbPFeyaH4xtb+VYLiRUdux60Ad8FpcYq0qwMuY3DVEyUAMzThTMYpwoAdSU7FJigBKSlooASijFFACrUmKYtSUAf/9H6FxSU40w0AJmk3UuM0xkoAlVqz7u8S3LmUhVCk5PqOlaKxqIjITyOa8q8Y6utxC1nC3O4HI9qAOJ8Sam99dGTJGc8VyYi8zmtZLWa6OXUjNblnoanG7igDjWspD91SaVLCUfeUivVINGij6YNLcaWGzhf0oA8zWwJpHsZF+6pNegLpW3tVlNPC9VoA8vNrIOWUip7Wc2c4cDkd6729sA2cLXL3WlnnAoA6fT/ABxPbPHDjcGYAnjoTXsMF/FcpuRgfpXylcxz2km5FJxXpHg/xHIQlvOdpOOtAHtmc09RTbfy5o96NmpcbaADFJijfSZoAKSnUUANxRinUmKABakpgp9AH//S+hDTTTqTFACrTm5qPOKeWRYy7HFAHIeKNdl0exkeFdzH5MezcZrxe1W4vLlZnDEe9egeJ9Rtbi9Nl5bMWz8wPH5VX0+zjt4NuBmgBsFsq9hWmkIPQUiCrsRoAkgi21eKA9qiVgKlWQUAQvEB2qq6Adq0Sd9QPFmgDGmUHtWTPED2renTbmsxl3UActeWivn5RXKsktneiRAQB6V6FcKFzXPXaB88UAd14V8SPKUtX6n1r0+QV816TcfYdWjkJwBX0TYXQvrUXHZuRQBIBThUgXNBXFADaWjFGKAClxRS0AIKdSUtAH//0/obFGKdijFAETLWPrMhhsXbOMVuGub8SjOmS4oA8tikFzdCU810qrmuS0lcYzXWiXbQBYSHNXYrY1lHUVh9Kmi11B6UAbQtTThZmorfVkl9K2oZlegCilqRT2ixWhJIErmtS1aa3z5abqAC6jQ53HFYzrGn3WzWFea1qM+cQt+lYjajqiNtEDH8qAOhu/mzWFKMUq394/8Aroiv1xUcsm+gDnrxSbjcOK918F3n2jRIos5MICn+deIXQ2nNeneAJvKtHTOfNYN9OKAPVIzT35pipinGgCPFGKdSUAJiilooAKKKKAP/1PovFGKdSUAMK5rC16Lfp0i10GcVn6pH5lm4oA8TtE8mQJVm8up45NkSFqbMQmo+UO3BreSNY5BMwBx60AY1pYy3+PtAMefWtQ+GbSNtpn/U0y61WV52itwq4ViDgYyK4221fV7i/WG7BOf4lGBQB6BHpkNp/q5N2Pc1s2k2zFc/jyv4s1NHdUAdDdXWc1js4k681VmuN3eoEmxQBZe4t7UbpQoUdyKz5fEmgocmaLd6Y/8ArVPJElyfmPWuQvtBRtQEqKCBmgDZmvrPUxujZcHuBWZJYwp9x805tNIPyDaPbinJbNH1zQBzl/HtzXb+CD9z8K53UrffGXrd8Hv5OygD281G1Njk8yPfSb80AFFFFACUUuKTFABRRRQB/9X6OpKXNJmgBMZpsqgxFDT92Khnk2xl6APGrqzaPX7pj0MnH5Ct2VN8BUUup4kvvOA9afG+6gDBisCH3HNXlsF80MFH5VtqgParCxj0oAwbi3NQw2bN610k1vmMvisw3cdpGZZCFUdzQBXOnN71DLYmNC/pWhDrMV1H5tvh19RWNc6+XuhYsoAbvgUASW0RetH7Nt5Ip9lHGsgQHNbFxDtzQBz8iD0rMuEBzxW1MuKy5jigDFukBtylJpIktow6jpU8w3VvadZhrEtj0oA6nR9Ree3CMMZreC4rktIGx1SuzdaAGCnCmgVIKAExSYp5pMUAMxRinYoxQB//1vovNGabRQAu0tVS94t2Sr6HFUb35s0AcJcQmooExWnefJms6N80AaMdXEGapxGtGIZoAdKR9nKVgT2STQFH71uTnbWcx3UAUbLTY4INiY/CpZoYkgIMa7vXAz+dX4UxTLpN2aAMOxBjuFc9q6t5BN0rmWHlVpWM+cUANuodua526+XNdZeODmuTvDnNAGYXrrtNulXTivHauIY4qwupC3tymaAOmstRC6ikdej+bvrxHRw13qUc4JxXskalKALYFOFMD5p45oAWkxTsUUANopaKAP/X+izTTUhFMIoAaDioZV31NszTlTFAHBatJsuDAvXk/lWVAwPStnxHbPazHUkG4n5Mezd64+O9WKURA5oA66Fq1YTXO28+a2oHzQBLdFOdxxWQ1xFH91gak1KNpM4JrnPsrjqTQBt/2mF6VVl1yHOwsN/pVeDT0l++2KsSWdtbj5drEd8UAZtxfO+cjFaOlP5mKy54/N6Vq6TEYcZoA17yMjNcteDGa6q9mBzXH30vWgDAubjy81z8lwbmbyQetT6hLukKCrug6C9xcpcYJFAHe+EtKMUayEdMV6ayZqhpVqLe32YrWAoArrHVhVqTFLQA0immnk0w0ANooooA/9D6QIpMVJRigBgGKGp+KTZQBm6nZrd2TRHvXg+qWM+nakFwdozzX0TjHWuS1/R49QRuACe9AHn9ldo+MNmuqtZM4rjP7JGlybNxOPc1u2Vz0oA6do/MqnLbY7Vctpg2KluGHNAHMXCSJ9wH8Khht3m/1mR9a6FSp7Ch4g3QUAZP2OOLoc1YiwOlLLGU61TNxsoAdevjNcdqE2M1qahqIXPNcncXH2nOO9AFO3t1vb5VJ617h4e0yK0twowTxXkmh6ez6jG3Ne7WluYsUAagX0pfu0oNMkoAXfRuquKeKAJM0U2igBaKM0UAf//R+kxTsU2nA0ALS5pOtIRQBHI1Vtu+pJPvbatxQoI97HFAHlniW2/0oke9czC5i616B4iNozMRIC/pXnjRO/bFAG1b6qIu9XG1dZe9ef3/AJsGdoNYq6vcRdQaAPVv7TCd6eNcVe4ryo65JJ97ioJNTJ/ioA9LvNeQ55Fcne6+yZ281yxuml7mm/Z2l9aALcmoyXnUEZqxaoUxmm2lgRjitX7MF9qAO38M2oeRJsdK9UJFeV+Hda0uyRbaedEk9D1r1C2mtLqHzYpA30oAeDQxzTR97AqUx0AQgU4ClK7aAaACilNNNABS02loA//S+ks0maQ0gGaAJVNRtMQ+wCnjjrXO6zrNtpitNvXzF6LQBp315ZWUJuLqVYyvrXl+t/EZ1RrfTGV1PRwARXFeJPFk+qyMSCAe3auHE5CdKAOsttX1DUNQWS7bcT6cD8q9EjQP2ryvRr+0WRY5I2Mn97PFel2l0eMUAV7+y8xiuK5q40MtnArvfPgeTDMA/wDdqw0fqv6UAeTt4dc9Aaj/AOEZkPrXraxp6D8qnVE/uj8qAPJYvDrx9Qa0otMMfUV6HMieg/KsyaMelAGJBa+1Q3sWzNbsQC1mamc5oA841IHztwOPeut8M+LX0qNYJg0kfc5/xrnL+APnNZsFpcyr5Fshc9TjsB1P4UAfS2meJNO1IB4m2E/wscmutR1dN4r49t7u5026WS0kJ29ySR+Ve1+GPGsdyi2uoToJW7AYoA9OkkzTEOaescEsJljcNVdDhsUAWDTDUmM00rQAwU6kC5p+00Af/9P6PalQ4peGOKY7Rx8MwB9KAHMdzba+ffiEkqaycMwHPGTivV9a8U6dpEbEzp569EPWvn7xH4ql1u+MrJjOewoAwXbNQE5oY5puKAL1gmLhXr03Tps4rzG3mEWK9A0N/OjD0AdXHZ6Y90LqRJTOOhD4X8q3ncydsVjwjEgattMPQBW2YpelXGiqIx0AVJKpOma02iqu0VAGS421j3nzZrenjrHnizmgDhtRBXOKpR6heQWhSJkVeP4fm/Oui1G2xGz1xcp7UAMkvWnOdu38KZBfyWk4ZFyR3qSGKN/vHFSTWMoBkjUsnrQB6RoPj65hVbaRflPc4r17SbyLUYRdbhivlAPtjwOKt2OtahYyD7PKwx2JJH5UAfXxeP8AhOaZ5inqa+eLXx9rsWPNdHX0C811Vj8Rrd8C7t3LeoIAoA9fBHanbq4S28caJKwV5lgz2c5P6Vpf8Jb4e/5/Y/zP+FAH/9T1DVvH2l2YJsf37DoykY/I15bq/jXV9WyQwiQ9gMH8xXGMVQ8NmoJJ93SgBtxNNIcyOzn1Yk/zqqo79anVoiczAsvoODSubc826lV9GOTQBFnFIZMU1jUDUAT791d14bvhFGsJrzwPtq7Z3zwXCsvagD3yGXfW7aDpXmOl+IIyA1wwQdya7ay1qzncC3kVwe4oA6lxTAmaj84NU0clAEbxVXeKtBnBqFjmgDAuhtzXPzTDdiuh1LcAcCuLu5o4wXZsMO1AGdq16qRtDxzXAzNV/VLp5rjfWO77qAFVzS7pCfvnHpk1CBTxQBZVEb7xxUwtoD/GKzJMnpTEDepoA2CkcfRs1C7ntVQE+tSZoAsxzEdeam88+lU1NSZoA//V81OfWm81ITTDQAlOBqMnFNMmKAJiajNCtupW4oAruuafD8nWnD5qCuKANBJyDV+01mWyuFdBwKwFbFL53zYoA9r0bxSL2RUmIXPrXoi+QYvMjcGvl63mETiVX+Ydga9P0HW7lLcNegxwHA3t0yeg/GgD0wS5qKS4ZWwozUEBR4fMVs1Vu7tbWA3B+8O1ADNVvreCyeWRwJB/CeteHajq0l1d7+gqfxHq15qF6XVWCnPA6VzmyTq4IoAuXEvmVTUUdKA2KAJMUVGZKTfmgB5oFIDS0APpc1HmlBzQBKpp+ai6UuaAP//W80JppoNIaAGsM1EYyanpwoAZDDJ/CCalkguD/Aa39LVTjIFdGyJ/dH5UAefQWl05CpGS3pV86VfKN08TIvqa6eYBUJUYPtXMXk0pYgu2PqaAIHsouzVfttKsPK8+4fOP4QSDWXGT61WndxLgE4+tAHRtq1tap9mtYPk9WAJ/Os572RyfmO3+7nj8qrrzFk1WFAHp/hLXVgh+zXEnRScsc8gVma34pmmnMUa5Q9xXnzO6yfKxH0NaUXMWTyaALDaky87AfwFPjuobnmdfl7gcGs1qYOOlAG2bKwk5hJRfRjk1DJp1svSQH86yWZh0JpFZvU0AaH9nwn+OhtLmA3xqWT1quhPrU8cknmBdxx6Z4oAqvDIn3VJqLbcH+A11ESqeoFXFRP7o/KgDkI7a5l+VIySe1StZ3cJ2yxlW9DXVyAKuVGD7U63+dcvyffmgDjjHcf3DTdlx/cNd0yJ/dH5UzYn90flQB//Z"

}

