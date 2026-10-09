//
//  MockServer.swift
//  SteadyExample
//
//  Created by Gaajar on 30/09/26.
//

import Steady

/// Stands in for a chat backend. Holds a fixed history and serves it in
/// pages with a delay, the way a real API would.
final class MockServer {
    /// Oldest first.
    private let history: [Message]
    private let delay: Duration

    init(messageCount: Int = 300, delay: Duration = .milliseconds(600)) {
        self.delay = delay
        // Repeat the sample conversation until there are enough messages.
        history = (0..<messageCount).map { index in
            let line = Self.conversation[index % Self.conversation.count]
            return Message(id: "m\(index)", message: line.text, isMe: line.isMe)
        }
    }

    /// The newest `count` messages, oldest first.
    func latest(count: Int = 30) async -> [Message] {
        try? await Task.sleep(for: delay)
        return Array(history.suffix(count))
    }

    /// Up to `count` messages older than `id`, oldest first. Empty once
    /// there is nothing older.
    func page(before id: Message.ID, count: Int = 30) async -> [Message] {
        try? await Task.sleep(for: delay)
        guard let end = history.firstIndex(where: { $0.id == id }) else { return [] }
        let start = max(0, end - count)
        return Array(history[start..<end])
    }

    /// A made-up conversation with a realistic mix of short replies and
    /// long messages, so rows need different heights.
    private static let conversation: [(isMe: Bool, text: String)] = [
        (false, "Hey! Are you free this weekend? A few of us are thinking of driving up to the hills on Saturday."),
        (true, "Maybe! Which hills, and how long is the drive?"),
        (false, "The place near the lake we went to two years ago, the one with the small café at the top of the trail. It's about three hours if we leave early and skip the highway traffic."),
        (true, "Oh I loved that place. The café had that ridiculous carrot cake."),
        (false, "Yes!! That's half the reason I want to go back honestly 😄"),
        (true, "Who else is coming?"),
        (false, "So far it's me, Riya, and Karan. Riya might bring her cousin, who's visiting from Pune for the week. Karan said he can drive if we split petrol, and his car fits five comfortably, or six if nobody minds being squashed in the back."),
        (true, "Five sounds better than six for a three hour drive, not going to lie."),
        (false, "Agreed. I'll tell Riya to check with her cousin first before we plan around it."),
        (true, "What time are you thinking of leaving?"),
        (false, "Karan wants to leave at 6. I said that's too early, but he pointed out that if we leave after 8 we'll sit in traffic until the toll plaza and lose an hour anyway. So we compromised on 6:30."),
        (true, "6:30 is fine. I'll just sleep in the car."),
        (false, "Ha, that was everyone's plan. Karan is going to be thrilled."),
        (true, "Should we bring food or eat on the way?"),
        (false, "Let's pack breakfast and snacks and eat lunch at the café. There's that dhaba on the way back too, the one with the huge parathas, if everyone's hungry again by evening."),
        (true, "Perfect. I can make sandwiches. Anyone vegetarian this time?"),
        (false, "Riya is, and I think the cousin is too. Karan eats everything."),
        (true, "Okay, I'll do half paneer and half chicken, and label them so nobody gets the wrong one."),
        (false, "You're the best. I'll bring fruit, chips, and a big flask of chai."),
        (true, "Weather looks okay? Last time it rained the whole way back and the road near the bridge was a mess."),
        (false, "Forecast says clear on Saturday, some clouds in the evening. Bring a jacket anyway, it gets cold at the top once the sun goes down, and we'll probably stay to watch the sunset if the sky is clear."),
        (true, "Noted. Do we need to book anything?"),
        (false, "Not really. The trail is free, and the café doesn't take bookings. Parking is the only problem on weekends, which is another reason Karan wants to get there early."),
        (true, "Fine, fine, Karan wins. 6:30 it is."),
        (false, "I'll make a group chat tonight so we can sort out pickups. Karan will probably start from his place, get Riya and her cousin, then you, then me since I'm closest to the highway."),
        (true, "Sounds good. Send me the pickup time once it's decided."),
        (false, "Will do. Also, Riya asked if you still have that portable speaker. She wants music for the drive and apparently Karan's car only plays the radio."),
        (true, "I do, I'll charge it on Friday. Tell her she's in charge of the playlist and nobody is allowed to complain."),
        (false, "She's going to take that very seriously. Expect a two hour playlist of 90s Bollywood."),
        (true, "Honestly? Perfect. See you Saturday! 🚗"),
    ]
}
