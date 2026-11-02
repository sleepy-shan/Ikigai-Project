import 'media.dart';

/// People/search models for the Search tabs (characters, staff, studios).
///
/// AniList exposes these as `Page.characters / staff / studios` with a
/// `FAVOURITES_DESC` sort, so an empty query returns the popular ranking
/// (Page 1) and a text query filters by name.
class SearchCharacter {
  const SearchCharacter({
    required this.id,
    required this.nameFull,
    this.nameNative,
    this.imageUrl = '',
    this.favourites = 0,
    this.mediaTitle = '',
  });

  final int id;
  final String nameFull;
  final String? nameNative;
  final String imageUrl;
  final int favourites;

  /// Most popular title the character appears in (card subtitle).
  final String mediaTitle;
}

class SearchStaff {
  const SearchStaff({
    required this.id,
    required this.nameFull,
    this.nameNative,
    this.imageUrl = '',
    this.favourites = 0,
    this.role = '',
    this.credits = 0,
  });

  final int id;
  final String nameFull;
  final String? nameNative;
  final String imageUrl;
  final int favourites;

  /// Primary occupation, e.g. "Voice Actor" or "Mangaka".
  final String role;

  /// Number of credited titles (production + voice roles).
  final int credits;
}

class SearchStudio {
  const SearchStudio({
    required this.id,
    required this.name,
    this.favourites = 0,
    this.isAnimationStudio = true,
    this.titleCount = 0,
  });

  final int id;
  final String name;
  final int favourites;
  final bool isAnimationStudio;

  /// Number of titles the studio produced.
  final int titleCount;
}

/// A page of character results plus pagination info.
class CharacterPage {
  const CharacterPage({
    required this.items,
    required this.page,
    required this.hasNextPage,
    this.total,
  });

  final List<SearchCharacter> items;
  final int page;
  final bool hasNextPage;

  /// Total matches reported by the API, if known.
  final int? total;

  static const CharacterPage empty = CharacterPage(
    items: [],
    page: 1,
    hasNextPage: false,
  );
}

/// A page of staff results plus pagination info.
class StaffPage {
  const StaffPage({
    required this.items,
    required this.page,
    required this.hasNextPage,
    this.total,
  });

  final List<SearchStaff> items;
  final int page;
  final bool hasNextPage;

  /// Total matches reported by the API, if known.
  final int? total;

  static const StaffPage empty = StaffPage(
    items: [],
    page: 1,
    hasNextPage: false,
  );
}

/// A page of studio results plus pagination info.
class StudioPage {
  const StudioPage({
    required this.items,
    required this.page,
    required this.hasNextPage,
    this.total,
  });

  final List<SearchStudio> items;
  final int page;
  final bool hasNextPage;

  /// Total matches reported by the API, if known.
  final int? total;

  static const StudioPage empty = StudioPage(
    items: [],
    page: 1,
    hasNextPage: false,
  );
}

/// Header details for a staff member or character page.
class PersonProfile {
  const PersonProfile({
    required this.id,
    required this.nameFull,
    this.nameNative,
    this.imageUrl = '',
    this.favourites = 0,
    this.role = '',
  });

  final int id;
  final String nameFull;
  final String? nameNative;
  final String imageUrl;
  final int favourites;

  /// Occupations for staff (e.g. "Voice Actor · Vocalist"); empty for
  /// characters.
  final String role;
}

/// A person (staff or character) together with one page of their titles.
class PersonWorks {
  const PersonWorks({required this.person, required this.works});

  final PersonProfile person;
  final MediaPage works;
}
