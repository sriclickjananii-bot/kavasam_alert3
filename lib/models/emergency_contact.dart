class EmergencyContact {
  final String id;
  final String name;
  final String phoneNumber; // E.164 format preferred, e.g. +91XXXXXXXXXX
  final bool isInvitedToLocationSharing;
  final bool invitationAccepted;
  final String? relation; // UI only: Father, Mother, ...

  EmergencyContact({
    required this.id,
    required this.name,
    required this.phoneNumber,
    this.isInvitedToLocationSharing = false,
    this.invitationAccepted = false,
    this.relation,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phoneNumber': phoneNumber,
        'isInvitedToLocationSharing': isInvitedToLocationSharing,
        'invitationAccepted': invitationAccepted,
        if (relation != null) 'relation': relation,
      };

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      id: json['id'] as String,
      name: json['name'] as String,
      phoneNumber: json['phoneNumber'] as String,
      isInvitedToLocationSharing:
          json['isInvitedToLocationSharing'] as bool? ?? false,
      invitationAccepted: json['invitationAccepted'] as bool? ?? false,
      relation: json['relation'] as String?,
    );
  }

  EmergencyContact copyWith({
    String? name,
    String? phoneNumber,
    bool? isInvitedToLocationSharing,
    bool? invitationAccepted,
    String? relation,
  }) {
    return EmergencyContact(
      id: id,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      isInvitedToLocationSharing:
          isInvitedToLocationSharing ?? this.isInvitedToLocationSharing,
      invitationAccepted: invitationAccepted ?? this.invitationAccepted,
    );
  }
}

/// Fixed list of public emergency helpline numbers dialed/messaged
/// alongside personal emergency contacts. Edit to match your region.
class PublicHelpline {
  final String label;
  final String number;
  const PublicHelpline(this.label, this.number);
}

const List<PublicHelpline> defaultPublicHelplines = [
  PublicHelpline('Police', '100'),
  PublicHelpline('Women Helpline', '1091'),
  PublicHelpline('Child Helpline', '1098'),
  PublicHelpline('National Emergency (All-in-one)', '112'),
];
