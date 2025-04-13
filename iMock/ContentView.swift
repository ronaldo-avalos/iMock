//
//  ContentView.swift
//  iMock
//
//  Created by Ronaldo Avalos on 12/04/25.
//

import SwiftUI
import AVKit
import AppKit

struct ContentView: View {
    @State private var videoURL: URL?
    @State private var player: AVPlayer?
    @State private var isTargeted = false
    @State private var isProcessing = false
    @State private var showExportAlert = false
    @State private var exportResultMessage = ""
    
    let allowedContentTypes: [UTType] = [.video, .movie, .mpeg4Movie, .quickTimeMovie]
    
    var body: some View {
        VStack {
            ZStack {
                GeometryReader { geometry in
                    if let currentUrl = videoURL {
                        let frameContentWidth: CGFloat = 1170 // AJUSTA ESTO
                        let frameContentHeight: CGFloat = 2532 // AJUSTA ESTO
                        let videoInset: CGFloat = 20
                        
                        let (drawWidth, drawHeight) = calculateDrawSize(
                            availableSize: geometry.size,
                            contentAspectRatio: frameContentHeight > 0 ? (frameContentWidth / frameContentHeight) : 1.0
                        )
                        iPhoneMockupView(
                            videoURL: currentUrl,
                            drawWidth: drawWidth,
                            drawHeight: drawHeight
                        )
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        .background(Color.white)

                    } else {
                        Text("Arrastra un archivo de video aquí")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 600, height: 600)
                .onDrop(of: allowedContentTypes, isTargeted: $isTargeted) { providers -> Bool in
                    handleDrop(providers: providers)
                    return true
                }
                .background(isTargeted ? Color.blue.opacity(0.3) : videoURL != nil ? Color.white : Color.gray.opacity(0.2))
                
                if isProcessing {
                    ProgressView("Exportando...")
                        .padding()
                        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .shadow(radius: 5)
                }
            }
            .padding()
            
            Spacer()
            if videoURL != nil && !isProcessing {
                Button("Exportar Video") {
                    exportVideo()
                }
                .padding()
                .disabled(isProcessing)
            }
            
            Spacer()
        }
        .frame(minWidth: 600, minHeight: 700)
        .alert("Exportación", isPresented: $showExportAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportResultMessage)
        }
    }
    
    
    private func calculateDrawSize(availableSize: CGSize, contentAspectRatio: CGFloat) -> (width: CGFloat, height: CGFloat) {
        let availableWidth = availableSize.width
        let availableHeight = availableSize.height
        let viewAspectRatio = availableHeight > 0 ? (availableWidth / availableHeight) : 1.0

        var drawWidth: CGFloat
        var drawHeight: CGFloat

        // Evitar división por cero si contentAspectRatio es inválido
        guard contentAspectRatio > 0 else {
            return (availableWidth, availableHeight) // Devolver tamaño completo como fallback
        }

        if contentAspectRatio > viewAspectRatio { // Contenido (marco) es más ancho relativo al espacio -> limita por ancho
            drawWidth = availableWidth
            drawHeight = drawWidth / contentAspectRatio
        } else { // Contenido (marco) es más alto relativo al espacio (o igual) -> limita por alto
            drawHeight = availableHeight
            drawWidth = drawHeight * contentAspectRatio
        }

        return (max(0, drawWidth), max(0, drawHeight)) // Asegurar que no sean negativos
    }

    
    // MARK: - Funciones de Ayuda
    func handleDrop(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        
        print("Provider registered types: \(provider.registeredTypeIdentifiers)")
        
        // Encuentra un identificador de tipo compatible con los que aceptamos
        // Da prioridad a los tipos específicos, luego a los generales como .movie o .video
        guard let compatibleType = provider.registeredTypeIdentifiers.first(where: { typeID in
            allowedContentTypes.contains(where: { $0.identifier == typeID }) ||
            UTType(typeID)?.conforms(to: .movie) ?? false || // Comprueba si conforma a "película"
            UTType(typeID)?.conforms(to: .video) ?? false    // Comprueba si conforma a "video"
        }) else {
            print("Error: Dropped item is not a recognized/compatible video type.")
            // TODO: Show error message to the user
            return
        }
        
        print("Attempting to load file representation for type: \(compatibleType)")
        
        // Usar loadFileRepresentation
        provider.loadFileRepresentation(forTypeIdentifier: compatibleType) { url, error in
            // Esta clausura puede ejecutarse en un hilo de fondo
            if let error = error {
                print("Error loading file representation: \(error.localizedDescription)")
                DispatchQueue.main.async { /* TODO: Show error */ }
                return
            }
            
            guard let sourceURL = url else {
                print("Failed to get URL from loadFileRepresentation.")
                DispatchQueue.main.async { /* TODO: Show error */ }
                return
            }
            
            // *** IMPORTANTE: sourceURL puede ser temporal. Cópialo. ***
            let fileManager = FileManager.default
            // Crear un nombre único en el directorio temporal de la app
            let destinationFileName = "dropped-\(UUID().uuidString)-\(sourceURL.lastPathComponent)"
            let destinationURL = fileManager.temporaryDirectory.appendingPathComponent(destinationFileName)
            
            do {
                // Si ya existe (poco probable con UUID), elimínalo primero
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                // Copia el archivo desde la URL (posiblemente temporal) a nuestra ubicación temporal
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                
                print("File successfully copied to temporary location: \(destinationURL.path)")
                
                // Ahora usa destinationURL en el hilo principal
                DispatchQueue.main.async {
                    // El acceso seguro puede seguir siendo necesario incluso para la copia temporal
                    if destinationURL.startAccessingSecurityScopedResource() {
                        print("Acceso seguro iniciado para la copia: \(destinationURL.path)")
                        self.videoURL = destinationURL
                        self.setupPlayer(url: destinationURL)
                        // Recuerda detener el acceso más tarde
                    } else {
                        print("ADVERTENCIA: No se pudo iniciar el acceso seguro a la copia \(destinationURL). Intentando usarla directamente.")
                        self.videoURL = destinationURL
                        self.setupPlayer(url: destinationURL)
                    }
                }
            } catch {
                print("Error copying temporary file: \(error)")
                DispatchQueue.main.async { /* TODO: Show error */ }
            }
        }
    }
    
    func setupPlayer(url: URL) {
        self.player = AVPlayer(url: url)
        self.player?.seek(to: .zero)

        // Opcional: iniciar reproducción automáticamente
        // self.player?.play()
    }
    
    func exportImageAsVideo(image: NSImage, duration: TimeInterval = 3.0, fps: Int = 30) throws -> URL {
        let size = image.size
        let frameCount = Int(duration * Double(fps))
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-video-\(UUID().uuidString).mp4")

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let pixelBuffer = image.toPixelBuffer()
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))

        for i in 0..<frameCount {
            let time = CMTimeMultiply(frameDuration, multiplier: Int32(i))
            while !input.isReadyForMoreMediaData {
                usleep(10_000)
            }
            if let buffer = pixelBuffer {
                adaptor.append(buffer, withPresentationTime: time)
            }
        }

        input.markAsFinished()
        writer.finishWriting {
            print("Exported snapshot video to: \(outputURL)")
        }

        return outputURL
    }

    func exportVideo() {
        guard let sourceURL = videoURL else { return } // El video original arrastrado

        isProcessing = true

        let videoProcessor = VideoProcessor()
        Task {
            var temporaryExportURL: URL? // Para limpieza en caso de error

            do {
                // 1. Exportar a la ubicación temporal (VideoProcessor se encarga de esto)
                let tempURL = try await videoProcessor.exportVideoWithFrame(
                    videoURL: sourceURL,
                    frameImageName: "iPhoneFrame"
                )
                temporaryExportURL = tempURL // Guarda para posible limpieza

                // 2. Presentar el NSSavePanel para que el usuario elija el destino
                //    presentSavePanel se encargará de MOVER el archivo desde tempURL
                //    a la ubicación elegida por el usuario.
                #if os(macOS)
                // ¡Asegúrate de que esta llamada se ejecute!
                let finalSavedURL = try await MainActor.run { // Ejecutar en hilo principal
                     try presentSavePanel(for: tempURL) // PASA la url temporal
                }
                #else
                // Lógica para iOS (Share Sheet, etc.) - Necesitarás implementarla
                print("Guardado en iOS no implementado todavía.")
                // Por ahora, solo informamos éxito con la URL temporal para iOS
                let finalSavedURL = tempURL
                // Considera implementar Share Sheet aquí para iOS
                #endif


                // 3. Si llegamos aquí, el guardado (y movimiento) fue exitoso
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.exportResultMessage = "Video exportado con éxito a: \(finalSavedURL.path)" // Usa la URL final
                    self.showExportAlert = true
                    print("Video guardado en: \(finalSavedURL.path)")

                    // Opcional: Mostrar en Finder (macOS)
                    #if os(macOS)
                    NSWorkspace.shared.activateFileViewerSelecting([finalSavedURL])
                    #endif

                    // Limpieza del archivo original arrastrado (si es una copia)
                    // Y detener el acceso seguro si se inició
                    if self.videoURL == temporaryExportURL { // Si videoURL era la copia temporal
                       try? FileManager.default.removeItem(at: self.videoURL!)
                    } else {
                       // Si videoURL era el original, solo detén el acceso
                       self.videoURL?.stopAccessingSecurityScopedResource()
                    }
                     // El archivo temporal de exportación (tempURL) ya fue MOVIDO por presentSavePanel, no necesita borrarse.

                     // Considera resetear el estado
                     // self.videoURL = nil
                     // self.player = nil
                }

            } catch let saveError as SavePanelError where saveError == .userCancelled {
                 // El usuario canceló el panel de guardado (macOS)
                 DispatchQueue.main.async {
                     self.isProcessing = false
                     print("Guardado cancelado por el usuario.")
                     // Limpiar el archivo temporal de EXPORTACIÓN si el usuario canceló
                     if let tempURL = temporaryExportURL { try? FileManager.default.removeItem(at: tempURL) }
                     self.videoURL?.stopAccessingSecurityScopedResource() // Detener acceso al original si aplica
                 }
            } catch {
                 // Cualquier otro error (exportación o guardado/movimiento)
                 DispatchQueue.main.async {
                     self.isProcessing = false
                     self.exportResultMessage = "Error durante la exportación/guardado: \(error.localizedDescription)"
                     self.showExportAlert = true
                     print("Error al exportar/guardar: \(error)")
                     // Limpiar el archivo temporal de EXPORTACIÓN si hubo error
                     if let tempURL = temporaryExportURL { try? FileManager.default.removeItem(at: tempURL) }
                     self.videoURL?.stopAccessingSecurityScopedResource() // Detener acceso al original si aplica
                 }
            }
        }
    }

    #if os(macOS)
    // Asegúrate de que esta función exista y sea EXACTAMENTE así
    @MainActor
    func presentSavePanel(for temporaryURL: URL) throws -> URL {
        let savePanel = NSSavePanel()
        savePanel.title = "Guardar Video Exportado"
        savePanel.prompt = "Guardar"
        savePanel.nameFieldStringValue = temporaryURL.lastPathComponent // Nombre sugerido
        // Tipos de archivo que permites guardar (ajusta si es necesario)
        savePanel.allowedContentTypes = [UTType.mpeg4Movie, UTType.quickTimeMovie]
        // Opcional: sugerir directorio inicial
        // savePanel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

        let response = savePanel.runModal()

        guard response == .OK else {
            // Usuario canceló
            throw SavePanelError.userCancelled
        }

        // Obtiene la URL ELEGIDA POR EL USUARIO
        guard let destinationURL = savePanel.url else {
            throw SavePanelError.couldNotCreatePanel
        }

        // Mueve el archivo desde la ubicación temporal a la ELEGIDA POR EL USUARIO
        do {
            // Elimina si ya existe en el destino elegido
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            // Mueve el archivo
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
            // Devuelve la URL final donde se guardó exitosamente
            return destinationURL
        } catch {
            print("Error al mover el archivo de \(temporaryURL.path) a \(destinationURL.path): \(error)")
            throw SavePanelError.moveFailed(error)
        }
    }

    // El enum SavePanelError (como estaba definido antes)
    enum SavePanelError: Error, LocalizedError {
        case userCancelled
        case couldNotCreatePanel
        case moveFailed(Error)
        // ... descripciones de error ...
        // Añadir equatable para la comparación en el catch
        static func == (lhs: SavePanelError, rhs: SavePanelError) -> Bool {
            switch (lhs, rhs) {
            case (.userCancelled, .userCancelled): return true
            case (.couldNotCreatePanel, .couldNotCreatePanel): return true
            case (.moveFailed, .moveFailed): return true // Podrías comparar errores internos si quisieras
            default: return false
            }
        }
    }
    #endif
}

extension NSImage {
    func toPixelBuffer() -> CVPixelBuffer? {
        let width = Int(size.width)
        let height = Int(size.height)
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!
        ] as CFDictionary

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                            kCVPixelFormatType_32ARGB, attrs,
                            &pixelBuffer)

        guard let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        let data = CVPixelBufferGetBaseAddress(buffer)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: data, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        else {
            return nil
        }

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        draw(at: .zero, from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        CVPixelBufferUnlockBaseAddress(buffer, [])

        return buffer
    }
}
extension View {
    func snapshot(size: CGSize) -> NSImage? {
        let view = NSHostingView(rootView: self.frame(width: size.width, height: size.height))
        let bounds = CGRect(origin: .zero, size: size)

        let rep = view.bitmapImageRepForCachingDisplay(in: bounds)!
        view.cacheDisplay(in: bounds, to: rep)

        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }
}

//struct VideoPlayerWithFrame: View {
//    let player: AVPlayer
//    let videoURL: URL // Mantenida por si se necesita más adelante
//
//    // Dimensiones intrínsecas del área de contenido del marco
//    let frameContentWidth: CGFloat = 1170 // AJUSTA ESTO
//    let frameContentHeight: CGFloat = 2532 // AJUSTA ESTO
//
//    var body: some View {
//        GeometryReader { geometry in
//            // --- Bloque de Cálculo (Se ejecuta antes de construir la vista) ---
//            let (drawWidth, drawHeight) = calculateDrawSize(
//                availableSize: geometry.size,
//                contentAspectRatio: frameContentHeight > 0 ? (frameContentWidth / frameContentHeight) : 1.0
//            )
//            // --- Fin Bloque de Cálculo ---
//
//            // --- Construcción de la Vista (Todo aquí debe ser View o modificador) ---
//            ZStack { // <- View
//                // Capa 1: Video Player
//                VideoPlayer(player: player) // <- View
//                    // Modificadores para VideoPlayer
//                    .frame(width: drawWidth, height: drawHeight)
//                    .clipped() // Buena idea añadir esto
//
//                // Capa 2: Marco del iPhone
//                Image("iPhoneFrame") // <- View
//                    // Modificadores para Image
//                    .resizable()
//                    .aspectRatio(contentMode: .fit)
//                    .frame(width: drawWidth, height: drawHeight) // Usar el mismo tamaño calculado
//            }
//            // Modificadores para el ZStack
//            .frame(width: drawWidth, height: drawHeight) // Dar tamaño al contenedor ZStack
//            .position(x: geometry.size.width / 2, y: geometry.size.height / 2) // Centrar el ZStack
//        }
//        // Modificadores para el GeometryReader
//        .onAppear {
//            player.play()
//        }
//        .onDisappear {
//            player.pause()
//        }
//    }
//
//    // Función auxiliar para mantener el cálculo separado (más limpio)
//}
#Preview {
    ContentView()
}
