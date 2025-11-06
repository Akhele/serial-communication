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
    // Faces & Expressions
    Avatar(id: 0, emoji: '😀', name: 'Happy'),
    Avatar(id: 1, emoji: '😎', name: 'Cool'),
    Avatar(id: 2, emoji: '🤩', name: 'Star Eyes'),
    Avatar(id: 3, emoji: '😈', name: 'Devil'),
    Avatar(id: 4, emoji: '🤠', name: 'Cowboy'),
    Avatar(id: 5, emoji: '🥷', name: 'Ninja'),
    Avatar(id: 6, emoji: '👻', name: 'Ghost'),
    Avatar(id: 7, emoji: '💀', name: 'Skull'),
    
    // Animals
    Avatar(id: 8, emoji: '🦊', name: 'Fox'),
    Avatar(id: 9, emoji: '🐼', name: 'Panda'),
    Avatar(id: 10, emoji: '🦁', name: 'Lion'),
    Avatar(id: 11, emoji: '🐯', name: 'Tiger'),
    Avatar(id: 12, emoji: '🐨', name: 'Koala'),
    Avatar(id: 13, emoji: '🐸', name: 'Frog'),
    Avatar(id: 14, emoji: '🦅', name: 'Eagle'),
    Avatar(id: 15, emoji: '🦈', name: 'Shark'),
    Avatar(id: 16, emoji: '🐺', name: 'Wolf'),
    Avatar(id: 17, emoji: '🦉', name: 'Owl'),
    
    // Fantasy & Creatures
    Avatar(id: 18, emoji: '🤖', name: 'Robot'),
    Avatar(id: 19, emoji: '👾', name: 'Alien'),
    Avatar(id: 20, emoji: '🦄', name: 'Unicorn'),
    Avatar(id: 21, emoji: '🐉', name: 'Dragon'),
    Avatar(id: 22, emoji: '🦋', name: 'Butterfly'),
    Avatar(id: 23, emoji: '👽', name: 'UFO'),
    
    // Symbols & Elements
    Avatar(id: 24, emoji: '🌟', name: 'Star'),
    Avatar(id: 25, emoji: '⚡', name: 'Lightning'),
    Avatar(id: 26, emoji: '🔥', name: 'Fire'),
    Avatar(id: 27, emoji: '💎', name: 'Diamond'),
    Avatar(id: 28, emoji: '⭐', name: 'Gold Star'),
    Avatar(id: 29, emoji: '💥', name: 'Boom'),
    Avatar(id: 30, emoji: '✨', name: 'Sparkle'),
    
    // Activities & Hobbies
    Avatar(id: 31, emoji: '🎮', name: 'Gamer'),
    Avatar(id: 32, emoji: '🎨', name: 'Artist'),
    Avatar(id: 33, emoji: '🎸', name: 'Guitarist'),
    Avatar(id: 34, emoji: '🎵', name: 'Music'),
    Avatar(id: 35, emoji: '⚽', name: 'Soccer'),
    Avatar(id: 36, emoji: '🏀', name: 'Basketball'),
    Avatar(id: 37, emoji: '🎯', name: 'Target'),
    Avatar(id: 38, emoji: '🏆', name: 'Trophy'),
    
    // Vehicles & Travel
    Avatar(id: 39, emoji: '🚀', name: 'Rocket'),
    Avatar(id: 40, emoji: '🏍️', name: 'Motorcycle'),
    Avatar(id: 41, emoji: '🚁', name: 'Helicopter'),
    Avatar(id: 42, emoji: '✈️', name: 'Plane'),
    Avatar(id: 43, emoji: '🚗', name: 'Car'),
    Avatar(id: 44, emoji: '🚲', name: 'Bike'),
    Avatar(id: 45, emoji: '⛵', name: 'Sailboat'),
    Avatar(id: 46, emoji: '🛸', name: 'UFO Ship'),
    
    // Food & Drink
    Avatar(id: 47, emoji: '🍕', name: 'Pizza'),
    Avatar(id: 48, emoji: '🍔', name: 'Burger'),
    Avatar(id: 49, emoji: '🍩', name: 'Donut'),
    Avatar(id: 50, emoji: '🍦', name: 'Ice Cream'),
    Avatar(id: 51, emoji: '☕', name: 'Coffee'),
    
    // Nature & Weather
    Avatar(id: 52, emoji: '🌙', name: 'Moon'),
    Avatar(id: 53, emoji: '☀️', name: 'Sun'),
    Avatar(id: 54, emoji: '🌊', name: 'Wave'),
    Avatar(id: 55, emoji: '🌵', name: 'Cactus'),
    Avatar(id: 56, emoji: '🍀', name: 'Clover'),
    Avatar(id: 57, emoji: '🌺', name: 'Flower'),
  ];

  static Avatar getById(int id) {
    if (id < 0 || id >= all.length) {
      return all[0]; // Default avatar
    }
    return all[id];
  }
}

