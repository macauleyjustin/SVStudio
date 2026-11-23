import Foundation

public enum VTSParameterCategory: String, CaseIterable, Sendable {
    case faceHead = "Head & Position"
    case eyesBrows = "Eyes & Brows"
    case mouth = "Mouth & Voice"
    case handsLeft = "Left Hand"
    case handsRight = "Right Hand"
    case armsBody = "Arms & Body"
}

public struct VTSParameterDef: Sendable, Equatable, Identifiable {
    public var id: String { vtsId }
    public let vtsId: String
    public let live2dIds: [String]
    public let name: String
    public let category: VTSParameterCategory
    public let min: Double
    public let defaultValue: Double
    public let max: Double

    public init(
        vtsId: String,
        live2dIds: [String],
        name: String,
        category: VTSParameterCategory,
        min: Double,
        defaultValue: Double,
        max: Double
    ) {
        self.vtsId = vtsId
        self.live2dIds = live2dIds
        self.name = name
        self.category = category
        self.min = min
        self.defaultValue = defaultValue
        self.max = max
    }
}

/// Complete catalog of VTube Studio default tracking inputs & Live2D Cubism standard parameters.
/// Allows SVStudio to drive any `.sat` avatar seamlessly whether rigged with VTS IDs or Cubism IDs.
public enum VTSParameterCatalog {
    public static let all: [VTSParameterDef] = [
        // Head & Position
        VTSParameterDef(vtsId: "FacePositionX", live2dIds: ["ParamBodyX", "FacePositionX"], name: "Face Position X", category: .faceHead, min: -10, defaultValue: 0, max: 10),
        VTSParameterDef(vtsId: "FacePositionY", live2dIds: ["ParamBodyY", "FacePositionY"], name: "Face Position Y", category: .faceHead, min: -10, defaultValue: 0, max: 10),
        VTSParameterDef(vtsId: "FacePositionZ", live2dIds: ["ParamBodyZ", "FacePositionZ"], name: "Face Position Z", category: .faceHead, min: -10, defaultValue: 0, max: 10),
        VTSParameterDef(vtsId: "FaceAngleX", live2dIds: ["ParamAngleX", "FaceAngleX"], name: "Head Turn X", category: .faceHead, min: -30, defaultValue: 0, max: 30),
        VTSParameterDef(vtsId: "FaceAngleY", live2dIds: ["ParamAngleY", "FaceAngleY"], name: "Head Pitch Y", category: .faceHead, min: -30, defaultValue: 0, max: 30),
        VTSParameterDef(vtsId: "FaceAngleZ", live2dIds: ["ParamAngleZ", "FaceAngleZ"], name: "Head Tilt Z", category: .faceHead, min: -30, defaultValue: 0, max: 30),

        // Eyes & Brows
        VTSParameterDef(vtsId: "EyeOpenLeft", live2dIds: ["ParamEyeLOpen", "EyeOpenLeft"], name: "Eye Open Left", category: .eyesBrows, min: 0, defaultValue: 1, max: 1),
        VTSParameterDef(vtsId: "EyeOpenRight", live2dIds: ["ParamEyeROpen", "EyeOpenRight"], name: "Eye Open Right", category: .eyesBrows, min: 0, defaultValue: 1, max: 1),
        VTSParameterDef(vtsId: "EyeSmileLeft", live2dIds: ["ParamEyeLSmile", "EyeSmileLeft"], name: "Eye Smile Left", category: .eyesBrows, min: 0, defaultValue: 0, max: 1),
        VTSParameterDef(vtsId: "EyeSmileRight", live2dIds: ["ParamEyeRSmile", "EyeSmileRight"], name: "Eye Smile Right", category: .eyesBrows, min: 0, defaultValue: 0, max: 1),
        VTSParameterDef(vtsId: "EyeLeftX", live2dIds: ["ParamEyeBallX", "EyeLeftX"], name: "Eye Gaze X", category: .eyesBrows, min: -1, defaultValue: 0, max: 1),
        VTSParameterDef(vtsId: "EyeLeftY", live2dIds: ["ParamEyeBallY", "EyeLeftY"], name: "Eye Gaze Y", category: .eyesBrows, min: -1, defaultValue: 0, max: 1),
        VTSParameterDef(vtsId: "EyeRightX", live2dIds: ["EyeRightX"], name: "Eye Right Gaze X", category: .eyesBrows, min: -1, defaultValue: 0, max: 1),
        VTSParameterDef(vtsId: "EyeRightY", live2dIds: ["EyeRightY"], name: "Eye Right Gaze Y", category: .eyesBrows, min: -1, defaultValue: 0, max: 1),
        VTSParameterDef(vtsId: "Brows", live2dIds: ["Brows"], name: "Brows Combined Y", category: .eyesBrows, min: -1, defaultValue: 0, max: 1),
        VTSParameterDef(vtsId: "BrowLeftY", live2dIds: ["ParamBrowLY", "BrowLeftY"], name: "Brow Left Y", category: .eyesBrows, min: -1, defaultValue: 0, max: 1),
        VTSParameterDef(vtsId: "BrowRightY", live2dIds: ["ParamBrowRY", "BrowRightY"], name: "Brow Right Y", category: .eyesBrows, min: -1, defaultValue: 0, max: 1),
        VTSParameterDef(vtsId: "BrowLeftAngle", live2dIds: ["ParamBrowLAngle", "BrowLeftAngle"], name: "Brow Left Angle", category: .eyesBrows, min: -1, defaultValue: 0, max: 1),
        VTSParameterDef(vtsId: "BrowRightAngle", live2dIds: ["ParamBrowRAngle", "BrowRightAngle"], name: "Brow Right Angle", category: .eyesBrows, min: -1, defaultValue: 0, max: 1),

        // Mouth, Cheeks, Tongue & Voice
        VTSParameterDef(vtsId: "MouthOpen", live2dIds: ["ParamMouthOpenY", "MouthOpen"], name: "Mouth Open", category: .mouth, min: 0, defaultValue: 0, max: 1),
        VTSParameterDef(vtsId: "MouthSmile", live2dIds: ["ParamMouthForm", "MouthSmile"], name: "Mouth Smile / Form", category: .mouth, min: -1, defaultValue: 0, max: 1),
        VTSParameterDef(vtsId: "MouthX", live2dIds: ["ParamMouthX", "MouthX"], name: "Mouth Shift X", category: .mouth, min: -1, defaultValue: 0, max: 1),
        VTSParameterDef(vtsId: "CheekPuff", live2dIds: ["ParamCheek", "CheekPuff"], name: "Cheek / Blush Puff", category: .mouth, min: 0, defaultValue: 0, max: 1),
        VTSParameterDef(vtsId: "TongueOut", live2dIds: ["ParamTongueOut", "TongueOut"], name: "Tongue Out", category: .mouth, min: 0, defaultValue: 0, max: 1),
        VTSParameterDef(vtsId: "VoiceVolume", live2dIds: ["VoiceVolume"], name: "Voice Volume", category: .mouth, min: 0, defaultValue: 0, max: 1),
        VTSParameterDef(vtsId: "VoiceFrequency", live2dIds: ["VoiceFrequency"], name: "Voice Frequency", category: .mouth, min: 0, defaultValue: 0, max: 1),

        // Body & Breath
        VTSParameterDef(vtsId: "ParamBodyAngleX", live2dIds: ["ParamBodyAngleX"], name: "Body Sway X", category: .armsBody, min: -10, defaultValue: 0, max: 10),
        VTSParameterDef(vtsId: "ParamBodyAngleY", live2dIds: ["ParamBodyAngleY"], name: "Body Bob Y", category: .armsBody, min: -10, defaultValue: 0, max: 10),
        VTSParameterDef(vtsId: "ParamBodyAngleZ", live2dIds: ["ParamBodyAngleZ"], name: "Body Tilt Z", category: .armsBody, min: -10, defaultValue: 0, max: 10),
        VTSParameterDef(vtsId: "ParamBreath", live2dIds: ["ParamBreath"], name: "Breathing", category: .armsBody, min: 0, defaultValue: 0, max: 1),
        VTSParameterDef(vtsId: "ParamArmLA", live2dIds: ["ParamArmLA", "ParamArmLShoulder"], name: "Arm Left Raise", category: .armsBody, min: -35, defaultValue: 0, max: 60),
        VTSParameterDef(vtsId: "ParamArmRA", live2dIds: ["ParamArmRA", "ParamArmRShoulder"], name: "Arm Right Raise", category: .armsBody, min: -60, defaultValue: 0, max: 35),

        // Left Hand & 5 Fingers (VTS Standard)
        VTSParameterDef(vtsId: "HandLeftFound", live2dIds: ["HandLeftFound"], name: "Left Hand Found", category: .handsLeft, min: 0, defaultValue: 0, max: 1),
        VTSParameterDef(vtsId: "HandLeftPositionX", live2dIds: ["HandLeftPositionX"], name: "Left Hand X", category: .handsLeft, min: -10, defaultValue: 0, max: 10),
        VTSParameterDef(vtsId: "HandLeftPositionY", live2dIds: ["HandLeftPositionY"], name: "Left Hand Y", category: .handsLeft, min: -10, defaultValue: 0, max: 10),
        VTSParameterDef(vtsId: "HandLeftPositionZ", live2dIds: ["HandLeftPositionZ"], name: "Left Hand Z", category: .handsLeft, min: -10, defaultValue: 0, max: 10),
        VTSParameterDef(vtsId: "HandLeftAngleZ", live2dIds: ["HandLeftAngleZ", "HandLeftAngle", "ParamHandLAngle"], name: "Left Hand Angle", category: .handsLeft, min: -180, defaultValue: 0, max: 180),
        VTSParameterDef(vtsId: "HandLeftOpen", live2dIds: ["HandLeftOpen", "ParamHandL"], name: "Left Hand Open", category: .handsLeft, min: 0, defaultValue: 0.65, max: 1),
        VTSParameterDef(vtsId: "HandLeftFinger_1_Thumb", live2dIds: ["HandLeftFinger_1_Thumb"], name: "L Thumb", category: .handsLeft, min: 0, defaultValue: 0.65, max: 1),
        VTSParameterDef(vtsId: "HandLeftFinger_2_Index", live2dIds: ["HandLeftFinger_2_Index"], name: "L Index", category: .handsLeft, min: 0, defaultValue: 0.65, max: 1),
        VTSParameterDef(vtsId: "HandLeftFinger_3_Middle", live2dIds: ["HandLeftFinger_3_Middle"], name: "L Middle", category: .handsLeft, min: 0, defaultValue: 0.65, max: 1),
        VTSParameterDef(vtsId: "HandLeftFinger_4_Ring", live2dIds: ["HandLeftFinger_4_Ring"], name: "L Ring", category: .handsLeft, min: 0, defaultValue: 0.65, max: 1),
        VTSParameterDef(vtsId: "HandLeftFinger_5_Pinky", live2dIds: ["HandLeftFinger_5_Pinky"], name: "L Pinky", category: .handsLeft, min: 0, defaultValue: 0.65, max: 1),

        // Right Hand & 5 Fingers (VTS Standard)
        VTSParameterDef(vtsId: "HandRightFound", live2dIds: ["HandRightFound"], name: "Right Hand Found", category: .handsRight, min: 0, defaultValue: 0, max: 1),
        VTSParameterDef(vtsId: "HandRightPositionX", live2dIds: ["HandRightPositionX"], name: "Right Hand X", category: .handsRight, min: -10, defaultValue: 0, max: 10),
        VTSParameterDef(vtsId: "HandRightPositionY", live2dIds: ["HandRightPositionY"], name: "Right Hand Y", category: .handsRight, min: -10, defaultValue: 0, max: 10),
        VTSParameterDef(vtsId: "HandRightPositionZ", live2dIds: ["HandRightPositionZ"], name: "Right Hand Z", category: .handsRight, min: -10, defaultValue: 0, max: 10),
        VTSParameterDef(vtsId: "HandRightAngleZ", live2dIds: ["HandRightAngleZ", "HandRightAngle", "ParamHandRAngle"], name: "Right Hand Angle", category: .handsRight, min: -180, defaultValue: 0, max: 180),
        VTSParameterDef(vtsId: "HandRightOpen", live2dIds: ["HandRightOpen", "ParamHandR"], name: "Right Hand Open", category: .handsRight, min: 0, defaultValue: 0.65, max: 1),
        VTSParameterDef(vtsId: "HandRightFinger_1_Thumb", live2dIds: ["HandRightFinger_1_Thumb"], name: "R Thumb", category: .handsRight, min: 0, defaultValue: 0.65, max: 1),
        VTSParameterDef(vtsId: "HandRightFinger_2_Index", live2dIds: ["HandRightFinger_2_Index"], name: "R Index", category: .handsRight, min: 0, defaultValue: 0.65, max: 1),
        VTSParameterDef(vtsId: "HandRightFinger_3_Middle", live2dIds: ["HandRightFinger_3_Middle"], name: "R Middle", category: .handsRight, min: 0, defaultValue: 0.65, max: 1),
        VTSParameterDef(vtsId: "HandRightFinger_4_Ring", live2dIds: ["HandRightFinger_4_Ring"], name: "R Ring", category: .handsRight, min: 0, defaultValue: 0.65, max: 1),
        VTSParameterDef(vtsId: "HandRightFinger_5_Pinky", live2dIds: ["HandRightFinger_5_Pinky"], name: "R Pinky", category: .handsRight, min: 0, defaultValue: 0.65, max: 1),

        // Inter-hand distance
        VTSParameterDef(vtsId: "HandDistance", live2dIds: ["HandDistance"], name: "Hands Distance", category: .armsBody, min: 0, defaultValue: 0, max: 10)
    ]

    public static let byVtsId: [String: VTSParameterDef] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.vtsId, $0) }
    )
}
