import SwiftUI

struct PodcastGridItem: View {
    let podcast: Podcast

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: podcast.imageUrl, size: .small)) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundColor(.gray)
                    }
            }
            .aspectRatio(1, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(podcast.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .foregroundColor(.primary)
                if let total = podcast.totalEpisodes {
                    Text("\(total) episodes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
