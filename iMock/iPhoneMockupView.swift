//
//  iPhoneMockupView.swift
//  iMock
//
//  Created by Ronaldo Avalos on 12/04/25.
//

import SwiftUI

struct iPhoneMockupView: View {
    let videoURL: URL
    let drawWidth: CGFloat
    let drawHeight: CGFloat

    var body: some View {
        let videoInset: CGFloat = 20

        ZStack {
            RoundedRectangle(cornerRadius: 40)
                .fill(Color.black.shadow(.drop(color: .black, radius: 9)))
                .frame(width: drawWidth - 10, height: drawHeight - videoInset)

            VideoPlayerView(
                video: .init(videoID: videoURL),
                size: CGSize(width: drawWidth - 10, height: drawHeight - videoInset)
            )
            .frame(width: drawWidth - 10, height: drawHeight - videoInset)

            Image("iPhoneFrame")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: drawWidth + videoInset, height: drawHeight + videoInset)
                .allowsHitTesting(false)
        }
        .frame(width: drawWidth, height: drawHeight)
        .background(Color.white)
    }
}
