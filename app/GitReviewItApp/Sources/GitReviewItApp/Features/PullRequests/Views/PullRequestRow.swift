import SwiftUI

struct PullRequestRow: View {
    let pullRequest: PullRequest
    
    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: pullRequest.updatedAt, relativeTo: Date())
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pullRequest.repositoryFullName)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(pullRequest.title)
                .font(.headline)
                .lineLimit(2)
            
            HStack(spacing: 4) {
                if let avatarURL = pullRequest.authorAvatarURL {
                    AsyncImage(url: avatarURL) { image in
                        image.resizable()
                    } placeholder: {
                        Color.gray.opacity(0.3)
                    }
                    .frame(width: 16, height: 16)
                    .clipShape(Circle())
                }
                
                Text(pullRequest.authorLogin)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text("•")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(relativeTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

