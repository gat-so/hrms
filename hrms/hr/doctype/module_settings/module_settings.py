# Copyright (c) 2026, Frappe Technologies Pvt. Ltd. and Contributors
# License: GNU General Public License v3. See license.txt

import frappe
from frappe.model.document import Document


# Mapping of field names to workspace names
HRMS_MODULE_MAP = {
	"enable_people": "People",
	"enable_leaves": "Leaves",
	"enable_payroll": "Payroll",
	"enable_expenses": "Expenses",
	"enable_recruitment": "Recruitment",
	"enable_shift_and_attendance": "Shift & Attendance",
	"enable_tenure": "Tenure",
	"enable_performance": "Performance",
	"enable_tax_and_benefits": "Tax & Benefits",
}

ERPNEXT_MODULE_MAP = {
	"enable_accounting": "Accounting",
	"enable_buying": "Buying",
	"enable_selling": "Selling",
	"enable_stock": "Stock",
	"enable_assets": "Assets",
	"enable_crm": "CRM",
	"enable_manufacturing": "Manufacturing",
	"enable_quality": "Quality",
	"enable_support": "Support",
	"enable_projects": "Projects",
}


class ModuleSettings(Document):
	# begin: auto-generated types
	# This code is auto-generated. Do not modify anything in this block.

	from typing import TYPE_CHECKING

	if TYPE_CHECKING:
		from frappe.types import DF

		enable_accounting: DF.Check
		enable_assets: DF.Check
		enable_buying: DF.Check
		enable_crm: DF.Check
		enable_expenses: DF.Check
		enable_leaves: DF.Check
		enable_manufacturing: DF.Check
		enable_payroll: DF.Check
		enable_people: DF.Check
		enable_performance: DF.Check
		enable_projects: DF.Check
		enable_quality: DF.Check
		enable_recruitment: DF.Check
		enable_selling: DF.Check
		enable_shift_and_attendance: DF.Check
		enable_stock: DF.Check
		enable_support: DF.Check
		enable_tax_and_benefits: DF.Check
		enable_tenure: DF.Check
	# end: auto-generated types

	def validate(self):
		if not self.enable_people:
			frappe.throw(frappe._("The People module cannot be disabled as it is required for core HR functionality."))

	def on_update(self):
		self.update_workspace_visibility()
		frappe.clear_cache()

	def update_workspace_visibility(self):
		for field, workspace_name in HRMS_MODULE_MAP.items():
			enabled = self.get(field)
			self.toggle_workspace(workspace_name, enabled)

		for field, workspace_name in ERPNEXT_MODULE_MAP.items():
			enabled = self.get(field)
			self.toggle_workspace(workspace_name, enabled)

	def toggle_workspace(self, workspace_name, enabled):
		try:
			workspace_doc = frappe.get_doc("Workspace", workspace_name)
			workspace_doc.flags.ignore_links = True
			workspace_doc.flags.ignore_validate = True
			workspace_doc.public = 1 if enabled else 0
			workspace_doc.save(ignore_permissions=True)
		except frappe.DoesNotExistError:
			pass
		except Exception:
			frappe.clear_messages()
