# Copyright (c) 2026, Frappe Technologies Pvt. Ltd. and Contributors
# See license.txt

import frappe
from frappe.tests import IntegrationTestCase


class TestModuleSettings(IntegrationTestCase):
	def test_people_module_cannot_be_disabled(self):
		settings = frappe.get_doc("Module Settings")
		settings.enable_people = 0
		self.assertRaises(frappe.ValidationError, settings.save)

	def test_module_can_be_disabled(self):
		settings = frappe.get_doc("Module Settings")
		settings.enable_buying = 0
		settings.save()

		settings.reload()
		self.assertEqual(settings.enable_buying, 0)

		# re-enable
		settings.enable_buying = 1
		settings.save()
