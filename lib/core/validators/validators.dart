class Validators {

  static String? requiredField(
    String? value,
    String fieldName,
  ) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }

    return null;
  }


  static String? email(String? value) {

    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }


    final regex = RegExp(
      r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
    );


    if (!regex.hasMatch(value.trim())) {
      return 'Enter a valid email';
    }


    return null;
  }


  static String? password(String? value) {

    if (value == null || value.isEmpty) {
      return 'Password is required';
    }


    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }


    return null;
  }


  static String? confirmPassword(
    String? password,
    String? confirmPassword,
  ) {

    if (confirmPassword == null ||
        confirmPassword.isEmpty) {

      return 'Confirm password is required';
    }


    if (password != confirmPassword) {

      return 'Passwords do not match';

    }


    return null;
  }


  static String? phone(String? value) {

    if (value == null || value.trim().isEmpty) {

      return 'Phone number is required';

    }


    if (value.length < 10) {

      return 'Enter a valid phone number';

    }


    return null;
  }


  static String? number(String? value) {

    if (value == null || value.trim().isEmpty) {

      return 'Value is required';

    }


    if (double.tryParse(value) == null) {

      return 'Enter a valid number';

    }


    return null;
  }
}