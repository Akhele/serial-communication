class Avatar {
  final int id;
  final String emoji;
  final String name;

  const Avatar({
    required this.id,
    required this.emoji,
    required this.name,
  });
}

// Predefined list of avatars
class Avatars {
  static const List<Avatar> all = [
    Avatar(id: 0, emoji: '😀', name: 'Happy'),
    Avatar(id: 1, emoji: '😎', name: 'Cool'),
    Avatar(id: 2, emoji: '🤖', name: 'Robot'),
    Avatar(id: 3, emoji: '👾', name: 'Alien'),
    Avatar(id: 4, emoji: '🦊', name: 'Fox'),
    Avatar(id: 5, emoji: '🐼', name: 'Panda'),
    Avatar(id: 6, emoji: '🦁', name: 'Lion'),
    Avatar(id: 7, emoji: '🐯', name: 'Tiger'),
    Avatar(id: 8, emoji: '🐨', name: 'Koala'),
    Avatar(id: 9, emoji: '🐸', name: 'Frog'),
    Avatar(id: 10, emoji: '🦄', name: 'Unicorn'),
    Avatar(id: 11, emoji: '🐉', name: 'Dragon'),
    Avatar(id: 12, emoji: '🦋', name: 'Butterfly'),
    Avatar(id: 13, emoji: '🌟', name: 'Star'),
    Avatar(id: 14, emoji: '⚡', name: 'Lightning'),
    Avatar(id: 15, emoji: '🔥', name: 'Fire'),
    Avatar(id: 16, emoji: '💎', name: 'Diamond'),
    Avatar(id: 17, emoji: '🎮', name: 'Gamer'),
    Avatar(id: 18, emoji: '🎨', name: 'Artist'),
    Avatar(id: 19, emoji: '🚀', name: 'Rocket'),
  ];

  static Avatar getById(int id) {
    if (id < 0 || id >= all.length) {
      return all[0]; // Default avatar
    }
    return all[id];
  }
}

