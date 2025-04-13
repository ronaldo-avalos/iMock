//
//  VideoProcessor.swift
//  iMock
//
//  Created by Ronaldo Avalos on 12/04/25.
//

import Foundation
import AVFoundation
import Combine

#if canImport(UIKit)
import UIKit // Para UIImage en iOS
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit // Para NSImage en macOS
typealias PlatformImage = NSImage
#endif

enum VideoProcessorError: Error, LocalizedError {
    case assetLoadFailed(String)
    case missingVideoTrack
    case compositionSetupFailed(String)
    case exportSessionCreationFailed
    case exportFailed(String)
    case frameImageNotFound
    case cgImageCreationFailed

    var errorDescription: String? {
        switch self {
        case .assetLoadFailed(let reason): return "No se pudo cargar el video: \(reason)"
        case .missingVideoTrack: return "El video no contiene una pista de video válida."
        case .compositionSetupFailed(let reason): return "Error al configurar la composición: \(reason)"
        case .exportSessionCreationFailed: return "No se pudo crear la sesión de exportación."
        case .exportFailed(let reason): return "La exportación falló: \(reason)"
        case .frameImageNotFound: return "No se encontró la imagen del marco."
        case .cgImageCreationFailed: return "No se pudo crear la imagen CGImage para el marco."
        }
    }
}


class VideoProcessor {

    func exportVideoWithFrame(videoURL: URL, frameImageName: String) async throws -> URL {

        // 1. Cargar el Asset de Video
        let asset = AVURLAsset(url: videoURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoProcessorError.missingVideoTrack
        }

        // 2. Cargar Propiedades del Video (Tamaño y Transformación)
        let videoSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let videoDuration = try await asset.load(.duration)

        // Ajustar tamaño y origen si el video está rotado
        let transformedVideoSize = videoSize.applying(preferredTransform)
        // Queremos dimensiones absolutas para el lienzo
        let naturalVideoSize = CGSize(width: abs(transformedVideoSize.width), height: abs(transformedVideoSize.height))

        // 3. Cargar la Imagen del Marco
        guard let frameImage = PlatformImage(named: frameImageName) else {
            throw VideoProcessorError.frameImageNotFound
        }
        // Convertir a CGImage (necesario para CALayer)
        var frameCGImage: CGImage?
        #if os(macOS)
        frameCGImage = frameImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else // iOS, tvOS, watchOS
        frameCGImage = frameImage.cgImage
        #endif
        guard let validFrameCGImage = frameCGImage else {
            throw VideoProcessorError.cgImageCreationFailed
        }
        let frameSize = CGSize(width: validFrameCGImage.width, height: validFrameCGImage.height)

        // 4. Crear la Composición Mutable
        let mixComposition = AVMutableComposition()

        // Añadir pista de video
        guard let compositionVideoTrack = mixComposition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let sourceVideoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoProcessorError.compositionSetupFailed("No se pudo añadir pista de video a la composición")
        }
        try compositionVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: sourceVideoTrack, at: .zero)

        // Añadir pista de audio (si existe)
        if let sourceAudioTrack = try await asset.loadTracks(withMediaType: .audio).first,
           let compositionAudioTrack = mixComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try compositionAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: sourceAudioTrack, at: .zero)
        }


        // 5. Crear la Composición de Video (Instrucciones y Capas)
        let videoComposition = AVMutableVideoComposition()
        // Usamos el tamaño del MARCO como tamaño de renderizado final
        videoComposition.renderSize = frameSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30) // 30 FPS, ajustar si es necesario

        // Crear la instrucción principal
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: videoDuration)

        // Crear la instrucción de capa para el VIDEO
        let videoLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)

        // --- Calcular Transformación para el Video DENTRO del Marco ---
        // Esto es crucial y depende de DÓNDE está el área transparente en tu frameImage.png
        // Asumamos (¡DEBES AJUSTAR ESTO!) que el video debe llenar un área específica.
        // Ejemplo: El área transparente empieza en (50, 100) y mide 1070x2332 dentro de una imagen de 1170x2532
        let contentRectInFrame = CGRect(x: 50, y: 100, width: 1070, height: 2332) // ¡AJUSTA ESTOS VALORES!

        let videoAspectRatio = naturalVideoSize.width / naturalVideoSize.height
        let contentBoxAspectRatio = contentRectInFrame.width / contentRectInFrame.height

        var scale: CGFloat = 1.0
        var translationX: CGFloat = contentRectInFrame.origin.x
        var translationY: CGFloat = contentRectInFrame.origin.y

        if videoAspectRatio > contentBoxAspectRatio { // Video más ancho que el hueco -> Ajustar al ancho
            scale = contentRectInFrame.width / naturalVideoSize.width
            let scaledHeight = naturalVideoSize.height * scale
            translationY += (contentRectInFrame.height - scaledHeight) / 2.0 // Centrar verticalmente
        } else { // Video más alto que el hueco (o igual) -> Ajustar al alto
            scale = contentRectInFrame.height / naturalVideoSize.height
            let scaledWidth = naturalVideoSize.width * scale
            translationX += (contentRectInFrame.width - scaledWidth) / 2.0 // Centrar horizontalmente
        }

        // Combinar escala, traslación y la transformación original del video
        var finalTransform = preferredTransform // Aplicar rotación/orientación original primero
        finalTransform = finalTransform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        finalTransform = finalTransform.concatenating(CGAffineTransform(translationX: translationX, y: translationY))

        videoLayerInstruction.setTransform(finalTransform, at: .zero)
        // ---------------------------------------------------------------

        instruction.layerInstructions = [videoLayerInstruction]
        videoComposition.instructions = [instruction]


        // 6. Añadir el Marco como una Capa de Core Animation
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: videoComposition.renderSize) // Tamaño del lienzo final

        let videoLayer = CALayer() // Capa base para el video (manejado por las instrucciones)
        videoLayer.frame = parentLayer.frame
        parentLayer.addSublayer(videoLayer)

        let frameLayer = CALayer() // Capa para el marco
        frameLayer.contents = validFrameCGImage
        frameLayer.frame = parentLayer.frame // El marco ocupa todo el lienzo
        frameLayer.contentsGravity = .resizeAspect // O ajusta según necesites
        parentLayer.addSublayer(frameLayer) // Añadir encima del video

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)


        // 7. Configurar y Ejecutar la Sesión de Exportación
        guard let exportSession = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoProcessorError.exportSessionCreationFailed
        }

       
        let outputFileName = "output_\(UUID().uuidString).mp4"
        // *** USA SIEMPRE EL DIRECTORIO TEMPORAL AQUÍ ***
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(outputFileName)

        // Limpiar si ya existe
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        exportSession.outputURL = outputURL // Exportar a temporal
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition

        await exportSession.export()

        switch exportSession.status {
        case .completed:
            print("Exportación temporal completada en: \(outputURL.path)")
            // *** DEVUELVE LA URL TEMPORAL - NO MUEVAS NADA AQUÍ ***
            return outputURL
        case .failed:
            throw VideoProcessorError.exportFailed(exportSession.error?.localizedDescription ?? "Desconocido")
        case .cancelled:
            throw VideoProcessorError.exportFailed("Exportación cancelada")
        default:
            throw VideoProcessorError.exportFailed("Estado de exportación desconocido")
        }
    }


    // Función auxiliar para mover a Descargas (Ejemplo macOS)
    private func moveFileToDownloads(temporaryURL: URL) throws -> URL {
        let fileManager = FileManager.default
        #if os(macOS)
        let downloadsDirectory = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        #else
        // En iOS, no hay un directorio de "Descargas" directo accesible así.
        // Podrías guardar en el directorio de Documentos de la app o usar el Share Sheet.
        // Devolvemos la URL temporal por ahora para iOS.
        print("iOS: Devolviendo URL temporal. Implementar guardado específico o Share Sheet.")
        return temporaryURL
        #endif

        let destinationURL = downloadsDirectory.appendingPathComponent(temporaryURL.lastPathComponent)

        // Evitar sobrescribir si ya existe (añadir sufijo)
        var finalDestinationURL = destinationURL
        var counter = 1
        while fileManager.fileExists(atPath: finalDestinationURL.path) {
            let fileName = temporaryURL.deletingPathExtension().lastPathComponent
            let fileExtension = temporaryURL.pathExtension
            let newFileName = "\(fileName)_\(counter).\(fileExtension)"
            finalDestinationURL = downloadsDirectory.appendingPathComponent(newFileName)
            counter += 1
        }

        try fileManager.moveItem(at: temporaryURL, to: finalDestinationURL)
        print("Archivo movido a Descargas: \(finalDestinationURL.path)")
        return finalDestinationURL
    }
}
