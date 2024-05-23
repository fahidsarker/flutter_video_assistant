enum MessageUser {
  bot,
  user
}

class Message {
  final MessageUser user;
  final String text;


  Message({
    required this.user,
    required this.text,
  });

  String toUIStr() {
    return '${user == MessageUser.bot ? 'VBot': 'You'}: $text';
  }

  String toHistoryStr() {
    return '${user == MessageUser.bot ? 'Assistant': 'User'}: $text';
  }

}