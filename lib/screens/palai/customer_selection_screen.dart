import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/palai_models.dart';
import '../../widgets/fast_route.dart';
import 'customer_palai/customer_goat_registration_screen.dart';

class CustomerSelectionScreen extends StatelessWidget {
  final Stream<List<PalaiCustomer>> customersStream;

  const CustomerSelectionScreen({
    super.key,
    required this.customersStream,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        title: const Text('Select Customer'),
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<PalaiCustomer>>(
        stream: customersStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: AppColors.primaryGreen,
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Unable to load customers.',
                style: AppTheme.body(
                  size: 14,
                  color: AppColors.error,
                ),
              ),
            );
          }

          final customers = snapshot.data ?? [];

          if (customers.isEmpty) {
            return Center(
              child: Text(
                'No active customers found.',
                style: AppTheme.body(
                  size: 14,
                  color: AppColors.textGrey,
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: customers.length,
            separatorBuilder: (_, __) =>
            const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final customer = customers[index];

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primaryGreen,
                    child: const Icon(
                      Icons.person,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(
                    customer.name,
                    style: AppTheme.body(
                      size: 15,
                      weight: FontWeight.w600,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      fastRoute(
                        CustomerGoatRegistrationScreen(
                          customerId: customer.id,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}