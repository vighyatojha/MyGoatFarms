import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/locale_provider.dart';

/// Small, key-based translation lookup — deliberately simple (no .arb /
/// codegen) so it's easy to extend to other screens later: just add a key
/// here and call `AppStrings.t(context, 'your_key')` anywhere.
///
/// Currently used by the Profile screen and the Home-screen profile
/// completion popup, since those are the two places this project asked
/// for the language toggle to affect.
class AppStrings {
  AppStrings._();

  static String t(BuildContext context, String key) {
    // read(), not watch() — this is called from event handlers (snackbar
    // messages after an upload/save) as well as from build(). watch()
    // throws if used outside a build method, which was silently turning
    // successful uploads into a false "failed, try again" toast. The
    // screen still updates instantly when the language toggle is tapped,
    // because the toggle itself holds a context.watch<LocaleProvider>()
    // in build(), which is what triggers the rebuild either way.
    final lang = context.read<LocaleProvider>().language.code;
    final entry = _translations[key];
    if (entry == null) return key;
    return entry[lang] ?? entry['en'] ?? key;
  }

  static const Map<String, Map<String, String>> _translations = {
    'profile_title': {'en': 'Your Profile', 'hi': 'आपकी प्रोफ़ाइल', 'gu': 'તમારી પ્રોફાઇલ'},
    'profile_complete': {'en': 'profile complete', 'hi': 'प्रोफ़ाइल पूर्ण', 'gu': 'પ્રોફાઇલ પૂર્ણ'},
    'tap_to_change_photo': {
      'en': 'Tap to change photo',
      'hi': 'फ़ोटो बदलने के लिए टैप करें',
      'gu': 'ફોટો બદલવા માટે ટૅપ કરો',
    },
    'your_details': {'en': 'Your Details', 'hi': 'आपका विवरण', 'gu': 'તમારી વિગતો'},
    'farm_name': {'en': 'Farm Name', 'hi': 'फार्म का नाम', 'gu': 'ફાર્મનું નામ'},
    'owner_name': {'en': 'Owner Name', 'hi': 'मालिक का नाम', 'gu': 'માલિકનું નામ'},
    'mobile_number': {'en': 'Mobile Number', 'hi': 'मोबाइल नंबर', 'gu': 'મોબાઇલ નંબર'},
    'email': {'en': 'Email', 'hi': 'ईमेल', 'gu': 'ઇમેઇલ'},
    'farm_address': {'en': 'Farm Address', 'hi': 'फार्म का पता', 'gu': 'ફાર્મનું સરનામું'},
    'save_changes': {'en': 'Save Changes', 'hi': 'बदलाव सहेजें', 'gu': 'ફેરફારો સાચવો'},
    'login_locked_note': {
      'en': 'Used for login — cannot be changed here.',
      'hi': 'लॉगिन के लिए उपयोग होता है — यहाँ बदला नहीं जा सकता।',
      'gu': 'લોગિન માટે વપરાય છે — અહીં બદલી શકાતું નથી.',
    },
    'complete_your_profile': {
      'en': 'Complete Your Profile',
      'hi': 'अपनी प्रोफ़ाइल पूरी करें',
      'gu': 'તમારી પ્રોફાઇલ પૂર્ણ કરો',
    },
    'farm_photo': {'en': 'Farm Photo / Logo', 'hi': 'फार्म फ़ोटो / लोगो', 'gu': 'ફાર્મ ફોટો / લોગો'},
    'add_photo': {'en': 'Add Photo', 'hi': 'फ़ोटो जोड़ें', 'gu': 'ફોટો ઉમેરો'},
    'done': {'en': 'Done', 'hi': 'पूर्ण', 'gu': 'પૂર્ણ'},
    'partners': {'en': 'Partners', 'hi': 'साझेदार', 'gu': 'ભાગીદારો'},
    'add_partner': {'en': '+ Add Partner', 'hi': '+ साझेदार जोड़ें', 'gu': '+ ભાગીદાર ઉમેરો'},
    'no_partners_yet': {
      'en': 'No partners added yet',
      'hi': 'अभी तक कोई साझेदार नहीं जोड़ा गया',
      'gu': 'હજુ સુધી કોઈ ભાગીદાર ઉમેર્યો નથી',
    },
    'language': {'en': 'App Language', 'hi': 'ऐप की भाषा', 'gu': 'ઍપની ભાષા'},
    'logout': {'en': 'Logout', 'hi': 'लॉगआउट', 'gu': 'લૉગઆઉટ'},
    'partner_name': {'en': 'Partner Name', 'hi': 'साझेदार का नाम', 'gu': 'ભાગીદારનું નામ'},
    'partner_mobile': {'en': 'Mobile Number', 'hi': 'मोबाइल नंबर', 'gu': 'મોબાઇલ નંબર'},
    'partner_email': {'en': 'Email', 'hi': 'ईमेल', 'gu': 'ઇમેઇલ'},
    'partner_password': {'en': 'Password', 'hi': 'पासवर्ड', 'gu': 'પાસવર્ડ'},
    'confirm_password': {
      'en': 'Confirm Password',
      'hi': 'पासवर्ड की पुष्टि करें',
      'gu': 'પાસવર્ડની પુષ્ટિ કરો',
    },
    'add': {'en': 'Add', 'hi': 'जोड़ें', 'gu': 'ઉમેરો'},
    'cancel': {'en': 'Cancel', 'hi': 'रद्द करें', 'gu': 'રદ કરો'},
    'remove_partner_q': {
      'en': 'Remove this partner?',
      'hi': 'इस साझेदार को हटायें?',
      'gu': 'આ ભાગીદારને દૂર કરવો?',
    },
    'remove': {'en': 'Remove', 'hi': 'हटायें', 'gu': 'દૂર કરો'},
    'profile_updated': {'en': 'Profile updated', 'hi': 'प्रोफ़ाइल अपडेट हो गई', 'gu': 'પ્રોફાઇલ અપડેટ થઈ'},
    'photo_updated': {'en': 'Photo updated', 'hi': 'फ़ोटो अपडेट हो गई', 'gu': 'ફોટો અપડેટ થયો'},
    'change_photo': {'en': 'Change Photo', 'hi': 'फ़ोटो बदलें', 'gu': 'ફોટો બદલો'},
    'remove_photo': {'en': 'Remove Photo', 'hi': 'फ़ोटो हटायें', 'gu': 'ફોટો દૂર કરો'},
    'not_complete_title': {
      'en': 'Your profile is not complete',
      'hi': 'आपकी प्रोफ़ाइल पूरी नहीं है',
      'gu': 'તમારી પ્રોફાઇલ પૂર્ણ નથી',
    },
    'not_complete_body': {
      'en': 'Add your farm photo, address and partner details so your profile is ready to use.',
      'hi': 'अपनी प्रोफ़ाइल तैयार करने के लिए फार्म फ़ोटो, पता और साझेदार विवरण जोड़ें।',
      'gu': 'તમારી પ્રોફાઇલ તૈયાર કરવા માટે ફાર્મ ફોટો, સરનામું અને ભાગીદારની વિગતો ઉમેરો.',
    },
    'complete_now': {'en': 'Complete Profile Now', 'hi': 'अभी प्रोफ़ाइल पूरी करें', 'gu': 'હવે પ્રોફાઇલ પૂર્ણ કરો'},
    'remind_later': {'en': 'Remind me later', 'hi': 'मुझे बाद में याद दिलाएं', 'gu': 'મને પછી યાદ કરાવો'},
  };
}
