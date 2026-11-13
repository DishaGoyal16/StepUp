import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/hostel.dart';
import '../../domain/profile_enums.dart';
import 'profile_form_controller.dart';

/// The profile questionnaire (hostel, fitness level, sports, ...). Rebuilds
/// from [controller]; inline errors appear after `controller.validate()`.
class ProfileFormFields extends StatelessWidget {
  const ProfileFormFields({
    super.key,
    required this.controller,
    this.includeName = false,
    this.onPickPhoto,
    this.nameController,
  });

  final ProfileFormController controller;

  /// Onboarding also asks for the name; registration already has it.
  final bool includeName;

  /// Opens the photo picker; null hides the photo row.
  final Future<void> Function()? onPickPhoto;

  /// Optional text controller for the name field (kept stable by the caller).
  final TextEditingController? nameController;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _build(context),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _error(BuildContext context, String field) {
    final msg = controller.showErrors ? controller.errorFor(field, includeName: includeName) : null;
    if (msg == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(msg, style: const TextStyle(color: AppColors.error, fontSize: 12)),
    );
  }

  Widget _build(BuildContext context) {
    final c = controller;
    final d = c.draft;
    final dir = c.directory;
    final hostel = c.selectedHostel;
    final hasBlockFromHostel = hostel?.block != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (includeName) ...[
          TextFormField(
            controller: nameController,
            initialValue: nameController == null ? d.displayName : null,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Full name',
              errorText: c.showErrors ? c.errorFor('name') : null,
            ),
            onChanged: c.setName,
          ),
        ],
        _label(context, 'Hostel'),
        if (dir == null)
          const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator())
        else ...[
          DropdownButtonFormField<String>(
            key: const ValueKey('hostel-dropdown'),
            initialValue: d.hostelId,
            isExpanded: true,
            hint: const Text('Select your hostel'),
            items: _hostelItems(dir),
            onChanged: c.setHostel,
            decoration: const InputDecoration(),
          ),
          if (dir.isFallback)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Showing the built-in hostel list. It will be checked again when you finish setup.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textMuted),
              ),
            ),
        ],
        _error(context, 'hostel'),
        if (hostel != null) ...[
          const SizedBox(height: 12),
          if (hasBlockFromHostel)
            Chip(label: Text('Block ${hostel.block}'))
          else
            TextFormField(
              key: ValueKey('block-${hostel.id}'),
              initialValue: d.block,
              decoration: const InputDecoration(
                labelText: 'Block / wing (optional)',
              ),
              maxLength: 20,
              onChanged: c.setBlock,
            ),
        ],
        _label(context, 'Fitness level'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in FitnessLevel.values)
              ChoiceChip(
                label: Text(f.label),
                selected: d.fitnessLevel == f,
                onSelected: (_) => c.setFitness(f),
              ),
          ],
        ),
        _error(context, 'fitness'),
        _label(context, 'Sports you are interested in'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in kSportsOptions)
              FilterChip(
                label: Text(s),
                selected: d.sportsInterests.contains(s),
                onSelected: (_) => c.toggleSport(s),
              ),
          ],
        ),
        _error(context, 'sports'),
        _label(context, 'Preferred activity'),
        DropdownButtonFormField<String>(
          key: const ValueKey('activity-dropdown'),
          initialValue: d.preferredActivity,
          isExpanded: true,
          hint: const Text('Select an activity'),
          items: [for (final s in kSportsOptions) DropdownMenuItem(value: s, child: Text(s))],
          onChanged: c.setPreferredActivity,
        ),
        _error(context, 'activity'),
        _label(context, 'Preferred time'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in PreferredTime.values)
              ChoiceChip(
                label: Text(t.label),
                selected: d.preferredTime == t,
                onSelected: (_) => c.setPreferredTime(t),
              ),
          ],
        ),
        _error(context, 'time'),
        _label(context, 'Buddy type'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final b in BuddyType.values)
              ChoiceChip(
                label: Text(b.label),
                selected: d.buddyType == b,
                onSelected: (_) => c.setBuddyType(b),
              ),
          ],
        ),
        _error(context, 'buddy'),
        _label(context, 'Short bio (optional)'),
        TextFormField(
          initialValue: d.bio,
          maxLength: kBioMaxLength,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'e.g. Early-morning runner, up for evening football'),
          onChanged: c.setBio,
        ),
        if (onPickPhoto != null) ...[
          _label(context, 'Profile photo (optional)'),
          Row(
            children: [
              _PhotoPreview(path: d.photoLocalPath, name: d.displayName),
              const SizedBox(width: 16),
              Expanded(
                child: SecondaryButton(
                  label: d.photoLocalPath == null ? 'Choose photo' : 'Change photo',
                  icon: Icons.photo_camera_outlined,
                  onPressed: onPickPhoto,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  List<DropdownMenuItem<String>> _hostelItems(HostelDirectory dir) {
    Widget heading(String text) => Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary),
        );
    DropdownMenuItem<String> item(Hostel h) => DropdownMenuItem(
          value: h.id,
          child: Text(h.label, overflow: TextOverflow.ellipsis),
        );
    return [
      DropdownMenuItem<String>(enabled: false, value: '__hostels__', child: heading('Hostels')),
      ...dir.general.map(item),
      DropdownMenuItem<String>(enabled: false, value: '__girls__', child: heading("Girls' hostels")),
      ...dir.girls.map(item),
    ];
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({required this.path, required this.name});

  final String? path;
  final String name;

  @override
  Widget build(BuildContext context) {
    final p = path;
    if (p != null && File(p).existsSync()) {
      return CircleAvatar(radius: 28, backgroundImage: FileImage(File(p)));
    }
    return AvatarCircle(name: name.isEmpty ? '?' : name, radius: 28);
  }
}
