# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [17.1.0-dev] - 2026-03-18

### Added
- **Module Settings**: New settings page allowing System Managers and HR Managers to enable/disable HRMS and ERPNext workspaces. Admins can now control which modules are visible in the sidebar navigation.
  - Covers 9 HRMS modules: People, Leaves, Payroll, Expenses, Recruitment, Shift & Attendance, Tenure, Performance, Tax & Benefits
  - Covers 10 ERPNext modules: Accounting, Buying, Selling, Stock, Assets, CRM, Manufacturing, Quality, Support, Projects
  - People module is protected and cannot be disabled (required for core HR functionality)
  - Module Settings link added to the People workspace sidebar for easy access
