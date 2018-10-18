/// Copyright (c) 2018 Razeware LLC
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
///
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import UIKit
import Firebase
import MessageKit
import FirebaseFirestore

final class ChatViewController: MessagesViewController {
  
  private let user: User
  private let channel: Channel

//  These properties are similar to those added to the channels view controller. The messages array is the data model and the listener handles clean up.
  private var messages: [Message] = []
  private var messageListener: ListenerRegistration?
  
  private let db = Firestore.firestore()
  private var reference: CollectionReference?


  deinit {
    //To clean things up add a deinit towards the top of the file:
    messageListener?.remove()
  }
  
  init(user: User, channel: Channel) {
    self.user = user
    self.channel = channel
    super.init(nibName: nil, bundle: nil)
    
    title = channel.name
  }
  
  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    /*The reference property is the point in the database where the messages are stored. The id property on the channel is optional because you might not yet have synced the channel. If the channel doesn’t exist in Firestore yet messages cannot be sent, so returning to the channel list makes the most sense.*/
    guard let id = channel.id else {
      navigationController?.popViewController(animated: true)
      return
    }
    
    reference = db.collection(["channels", id, "thread"].joined(separator: "/"))

    
    // Firestore calls this snapshot listener whenever there is a change to the database.
    messageListener = reference?.addSnapshotListener { querySnapshot, error in
      guard let snapshot = querySnapshot else {
        print("Error listening for channel updates: \(error?.localizedDescription ?? "No error")")
        return
      }
      
      snapshot.documentChanges.forEach { change in
        self.handleDocumentChange(change)
      }
    }

    
    navigationItem.largeTitleDisplayMode = .never
    
    maintainPositionOnKeyboardFrameChanged = true
    messageInputBar.inputTextView.tintColor = .primary
    messageInputBar.sendButton.setTitleColor(.primary, for: .normal)
    
    messageInputBar.delegate = self
    messagesCollectionView.messagesDataSource = self
    messagesCollectionView.messagesLayoutDelegate = self
    messagesCollectionView.messagesDisplayDelegate = self

  }

  
  // MARK: - Helpers
  private func save(_ message: Message) {
    /*This method uses the reference that was just setup. The addDocument method on the reference takes a dictionary with the keys and values that represent that data. The message data struct implements DatabaseRepresentation, which defines a dictionary property to fill out.*/
    reference?.addDocument(data: message.representation) { error in
      if let e = error {
        print("Error sending message: \(e.localizedDescription)")
        return
      }
      
      self.messagesCollectionView.scrollToBottom()
    }
  }

  private func insertNewMessage(_ message: Message) {
    /*This helper method is similar to the one that’s in ChannelsViewController. It makes sure the messages array doesn’t already contain the message, then adds it to the collection view. Then, if the new message is the latest and the collection view is at the bottom, scroll to reveal the new message.*/
    guard !messages.contains(message) else {
      return
    }
    
    messages.append(message)
    messages.sort()
    
    let isLatestMessage = messages.index(of: message) == (messages.count - 1)
    let shouldScrollToBottom = messagesCollectionView.isAtBottom && isLatestMessage
    
    messagesCollectionView.reloadData()
    
    if shouldScrollToBottom {
      DispatchQueue.main.async {
        self.messagesCollectionView.scrollToBottom(animated: true)
      }
    }
  }

  private func handleDocumentChange(_ change: DocumentChange) {
    guard let message = Message(document: change.document) else {
      return
    }
    
    switch change.type {
    case .added:
      insertNewMessage(message)
      
    default:
      break
    }
  }

}

// MARK: - MessagesDisplayDelegate

extension ChatViewController: MessagesDisplayDelegate {
  
  func backgroundColor(for message: MessageType, at indexPath: IndexPath,
                       in messagesCollectionView: MessagesCollectionView) -> UIColor {
    
    // 1 For the given message, you check and see if it’s from the current sender. If it is, you return the app’s primary green color; if not, you return a muted gray color. MessageKit uses this color when creating the background image for the message.
    return isFromCurrentSender(message: message) ? .primary : .incomingMessage
  }
  
  func shouldDisplayHeader(for message: MessageType, at indexPath: IndexPath,
                           in messagesCollectionView: MessagesCollectionView) -> Bool {
    
    // 2 You return false to remove the header from each message. You can use this to display thread specific information, such as a timestamp.
    return false
  }
  
  func messageStyle(for message: MessageType, at indexPath: IndexPath,
                    in messagesCollectionView: MessagesCollectionView) -> MessageStyle {
    
    let corner: MessageStyle.TailCorner = isFromCurrentSender(message: message) ? .bottomRight : .bottomLeft
    
    // 3 Finally, based on who sent the message, you choose a corner for the tail of the message bubble.
    return .bubbleTail(corner, .curved)
  }
}

// MARK: - MessagesDataSource

extension ChatViewController: MessagesDataSource {
  
  // 1 A sender is a simple struct that has an id and name property. You create an instance of a sender from the anonymous Firebase user id and the chosen display name.
  func currentSender() -> Sender {
    return Sender(id: user.uid, displayName: AppSettings.displayName)
  }
  
  // 2 The number of messages in the collection view will be equal to the local array of messages.
  func numberOfMessages(in messagesCollectionView: MessagesCollectionView) -> Int {
    return messages.count
  }
  
  // 3 Your Message model object conforms to MessageType so you can just return the message for the given index path.
  func messageForItem(at indexPath: IndexPath,
                      in messagesCollectionView: MessagesCollectionView) -> MessageType {
    
    return messages[indexPath.section]
  }
  
  // 4 The last method returns the attributed text for the name above each message bubble. You can modify the text you’re returning here to your liking, but these are some good defaults.
  func cellTopLabelAttributedText(for message: MessageType,
                                  at indexPath: IndexPath) -> NSAttributedString? {
    
    let name = message.sender.displayName
    return NSAttributedString(
      string: name,
      attributes: [
        .font: UIFont.preferredFont(forTextStyle: .caption1),
        .foregroundColor: UIColor(white: 0.3, alpha: 1)
      ]
    )
  }
}


// MARK: - MessageInputBarDelegate

extension ChatViewController: MessageInputBarDelegate {
  func messageInputBar(_ inputBar: MessageInputBar, didPressSendButtonWith text: String) {
    
    // 1 Create a message from the contents of the message bar and the current user.
    let message = Message(user: user, content: text)
    
    // 2 Save the message to Cloud Firestore using save(_:).
    save(message)
    
    // 3 Clear the message bar’s input field after you send the message.
    inputBar.inputTextView.text = ""
  }

}

// MARK: - UIImagePickerControllerDelegate

extension ChatViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
  
}


// MARK: - MessagesLayoutDelegate

extension ChatViewController: MessagesLayoutDelegate {
  
  func avatarSize(for message: MessageType, at indexPath: IndexPath,
                  in messagesCollectionView: MessagesCollectionView) -> CGSize {
    
    // 1 Returning zero for the avatar size will hide it from the view.
    return .zero
  }
  
  func footerViewSize(for message: MessageType, at indexPath: IndexPath,
                      in messagesCollectionView: MessagesCollectionView) -> CGSize {
    
    // 2 Adding a little padding on the bottom of each message will help the readability of the chat.
    return CGSize(width: 0, height: 8)
  }
  
  func heightForLocation(message: MessageType, at indexPath: IndexPath,
                         with maxWidth: CGFloat, in messagesCollectionView: MessagesCollectionView) -> CGFloat {
    
    // 3 At the time of writing, MessageKit doesn’t have a default implementation for the height of a location message. Since you won’t be sending a location message in this tutorial, return zero as the default.
    return 0
  }
}
