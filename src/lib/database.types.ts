export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      account_fs_map: {
        Row: {
          account_id: string
          company_id: string
          created_at: string
          created_by: string | null
          display_order: number
          effective_from: string | null
          effective_to: string | null
          fs_structure_id: string
          id: string
          statement: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          account_id: string
          company_id: string
          created_at?: string
          created_by?: string | null
          display_order?: number
          effective_from?: string | null
          effective_to?: string | null
          fs_structure_id: string
          id?: string
          statement: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          account_id?: string
          company_id?: string
          created_at?: string
          created_by?: string | null
          display_order?: number
          effective_from?: string | null
          effective_to?: string | null
          fs_structure_id?: string
          id?: string
          statement?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "account_fs_map_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "account_fs_map_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "account_fs_map_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "account_fs_map_fs_structure_id_fkey"
            columns: ["fs_structure_id"]
            isOneToOne: false
            referencedRelation: "fs_structure"
            referencedColumns: ["id"]
          },
        ]
      }
      account_mapping: {
        Row: {
          account_id: string
          branch_id: string | null
          company_id: string
          created_at: string
          created_by: string | null
          document_type: string | null
          effective_from: string | null
          effective_to: string | null
          id: string
          item_group_id: string | null
          item_id: string | null
          key_code: string
          party_id: string | null
          reason_code: string | null
          source: string
          tax_profile_id: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          account_id: string
          branch_id?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          document_type?: string | null
          effective_from?: string | null
          effective_to?: string | null
          id?: string
          item_group_id?: string | null
          item_id?: string | null
          key_code: string
          party_id?: string | null
          reason_code?: string | null
          source?: string
          tax_profile_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          account_id?: string
          branch_id?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          document_type?: string | null
          effective_from?: string | null
          effective_to?: string | null
          id?: string
          item_group_id?: string | null
          item_id?: string | null
          key_code?: string
          party_id?: string | null
          reason_code?: string | null
          source?: string
          tax_profile_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "account_mapping_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "account_mapping_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "account_mapping_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "account_mapping_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "account_mapping_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "account_mapping_key_code_fkey"
            columns: ["key_code"]
            isOneToOne: false
            referencedRelation: "ref_mapping_key"
            referencedColumns: ["key_code"]
          },
        ]
      }
      amortization_entries: {
        Row: {
          amount: number
          company_id: string
          created_at: string
          entry_date: string
          id: string
          je_id: string | null
          period_number: number
          schedule_id: string
          status: string
        }
        Insert: {
          amount: number
          company_id: string
          created_at?: string
          entry_date: string
          id?: string
          je_id?: string | null
          period_number: number
          schedule_id: string
          status?: string
        }
        Update: {
          amount?: number
          company_id?: string
          created_at?: string
          entry_date?: string
          id?: string
          je_id?: string | null
          period_number?: number
          schedule_id?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "amortization_entries_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "amortization_entries_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "amortization_entries_je_id_fkey"
            columns: ["je_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "amortization_entries_schedule_id_fkey"
            columns: ["schedule_id"]
            isOneToOne: false
            referencedRelation: "amortization_schedules"
            referencedColumns: ["id"]
          },
        ]
      }
      amortization_schedules: {
        Row: {
          asset_account_id: string
          branch_id: string | null
          company_id: string
          created_at: string
          created_by: string | null
          description: string | null
          expense_account_id: string
          id: string
          posted_periods: number
          schedule_name: string
          start_date: string
          status: string
          total_amount: number
          total_periods: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          asset_account_id: string
          branch_id?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          expense_account_id: string
          id?: string
          posted_periods?: number
          schedule_name: string
          start_date: string
          status?: string
          total_amount: number
          total_periods: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          asset_account_id?: string
          branch_id?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          expense_account_id?: string
          id?: string
          posted_periods?: number
          schedule_name?: string
          start_date?: string
          status?: string
          total_amount?: number
          total_periods?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "amortization_schedules_asset_account_id_fkey"
            columns: ["asset_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "amortization_schedules_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "amortization_schedules_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "amortization_schedules_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "amortization_schedules_expense_account_id_fkey"
            columns: ["expense_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      approval_instances: {
        Row: {
          acted_at: string | null
          actual_approver_id: string | null
          approver_role_code: string | null
          company_id: string
          created_at: string | null
          created_by: string | null
          escalated_at: string | null
          id: string
          remarks: string | null
          request_id: string | null
          required_approver_id: string | null
          required_approver_type: string
          source_document_amount: number | null
          source_document_id: string
          source_document_no: string
          source_document_type: string
          status: string
          step_sequence: number
          submitted_at: string
          workflow_id: string
          workflow_step_id: string | null
        }
        Insert: {
          acted_at?: string | null
          actual_approver_id?: string | null
          approver_role_code?: string | null
          company_id: string
          created_at?: string | null
          created_by?: string | null
          escalated_at?: string | null
          id?: string
          remarks?: string | null
          request_id?: string | null
          required_approver_id?: string | null
          required_approver_type: string
          source_document_amount?: number | null
          source_document_id: string
          source_document_no: string
          source_document_type: string
          status?: string
          step_sequence: number
          submitted_at?: string
          workflow_id: string
          workflow_step_id?: string | null
        }
        Update: {
          acted_at?: string | null
          actual_approver_id?: string | null
          approver_role_code?: string | null
          company_id?: string
          created_at?: string | null
          created_by?: string | null
          escalated_at?: string | null
          id?: string
          remarks?: string | null
          request_id?: string | null
          required_approver_id?: string | null
          required_approver_type?: string
          source_document_amount?: number | null
          source_document_id?: string
          source_document_no?: string
          source_document_type?: string
          status?: string
          step_sequence?: number
          submitted_at?: string
          workflow_id?: string
          workflow_step_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "approval_instances_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_instances_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "approval_instances_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "approval_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_instances_workflow_id_fkey"
            columns: ["workflow_id"]
            isOneToOne: false
            referencedRelation: "approval_workflows"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_instances_workflow_step_id_fkey"
            columns: ["workflow_step_id"]
            isOneToOne: false
            referencedRelation: "approval_workflow_steps"
            referencedColumns: ["id"]
          },
        ]
      }
      approval_requests: {
        Row: {
          action_type: string
          branch_id: string | null
          company_id: string
          consumed_at: string | null
          consumed_by: string | null
          consumption_idempotency_key: string | null
          created_at: string
          currency_code: string | null
          current_step_sequence: number
          decided_at: string | null
          decision_reason: string | null
          id: string
          module_type: string
          record_snapshot: Json
          record_version: string
          request_reason: string | null
          requester_id: string
          requester_role_code: string
          source_document_amount: number | null
          source_document_id: string
          source_document_no: string
          source_document_type: string
          status: string
          submitted_at: string
          updated_at: string
          workflow_id: string
        }
        Insert: {
          action_type: string
          branch_id?: string | null
          company_id: string
          consumed_at?: string | null
          consumed_by?: string | null
          consumption_idempotency_key?: string | null
          created_at?: string
          currency_code?: string | null
          current_step_sequence: number
          decided_at?: string | null
          decision_reason?: string | null
          id?: string
          module_type: string
          record_snapshot?: Json
          record_version: string
          request_reason?: string | null
          requester_id: string
          requester_role_code: string
          source_document_amount?: number | null
          source_document_id: string
          source_document_no: string
          source_document_type: string
          status?: string
          submitted_at?: string
          updated_at?: string
          workflow_id: string
        }
        Update: {
          action_type?: string
          branch_id?: string | null
          company_id?: string
          consumed_at?: string | null
          consumed_by?: string | null
          consumption_idempotency_key?: string | null
          created_at?: string
          currency_code?: string | null
          current_step_sequence?: number
          decided_at?: string | null
          decision_reason?: string | null
          id?: string
          module_type?: string
          record_snapshot?: Json
          record_version?: string
          request_reason?: string | null
          requester_id?: string
          requester_role_code?: string
          source_document_amount?: number | null
          source_document_id?: string
          source_document_no?: string
          source_document_type?: string
          status?: string
          submitted_at?: string
          updated_at?: string
          workflow_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "approval_requests_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_requests_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_requests_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "approval_requests_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "approval_requests_workflow_id_fkey"
            columns: ["workflow_id"]
            isOneToOne: false
            referencedRelation: "approval_workflows"
            referencedColumns: ["id"]
          },
        ]
      }
      approval_workflow_steps: {
        Row: {
          action_required: string
          approver_role_code: string | null
          approver_role_id: string | null
          approver_type: string
          approver_user_id: string | null
          company_id: string
          created_at: string | null
          escalation_hours: number | null
          id: string
          is_active: boolean
          step_sequence: number
          updated_at: string
          updated_by: string | null
          workflow_id: string
        }
        Insert: {
          action_required?: string
          approver_role_code?: string | null
          approver_role_id?: string | null
          approver_type: string
          approver_user_id?: string | null
          company_id: string
          created_at?: string | null
          escalation_hours?: number | null
          id?: string
          is_active?: boolean
          step_sequence: number
          updated_at?: string
          updated_by?: string | null
          workflow_id: string
        }
        Update: {
          action_required?: string
          approver_role_code?: string | null
          approver_role_id?: string | null
          approver_type?: string
          approver_user_id?: string | null
          company_id?: string
          created_at?: string | null
          escalation_hours?: number | null
          id?: string
          is_active?: boolean
          step_sequence?: number
          updated_at?: string
          updated_by?: string | null
          workflow_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "approval_workflow_steps_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_workflow_steps_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "approval_workflow_steps_workflow_id_fkey"
            columns: ["workflow_id"]
            isOneToOne: false
            referencedRelation: "approval_workflows"
            referencedColumns: ["id"]
          },
        ]
      }
      approval_workflows: {
        Row: {
          action_type: string
          branch_id: string | null
          company_id: string
          created_at: string | null
          created_by: string | null
          currency_code: string | null
          document_type: string
          effective_from: string | null
          effective_to: string | null
          enforce_requester_separation: boolean
          id: string
          is_active: boolean | null
          module_type: string
          priority: number
          requester_role_code: string | null
          requester_user_id: string | null
          threshold_value: number | null
          trigger_condition_type: string
          updated_at: string | null
          updated_by: string | null
          workflow_name: string
        }
        Insert: {
          action_type?: string
          branch_id?: string | null
          company_id: string
          created_at?: string | null
          created_by?: string | null
          currency_code?: string | null
          document_type: string
          effective_from?: string | null
          effective_to?: string | null
          enforce_requester_separation?: boolean
          id?: string
          is_active?: boolean | null
          module_type: string
          priority?: number
          requester_role_code?: string | null
          requester_user_id?: string | null
          threshold_value?: number | null
          trigger_condition_type: string
          updated_at?: string | null
          updated_by?: string | null
          workflow_name: string
        }
        Update: {
          action_type?: string
          branch_id?: string | null
          company_id?: string
          created_at?: string | null
          created_by?: string | null
          currency_code?: string | null
          document_type?: string
          effective_from?: string | null
          effective_to?: string | null
          enforce_requester_separation?: boolean
          id?: string
          is_active?: boolean | null
          module_type?: string
          priority?: number
          requester_role_code?: string | null
          requester_user_id?: string | null
          threshold_value?: number | null
          trigger_condition_type?: string
          updated_at?: string | null
          updated_by?: string | null
          workflow_name?: string
        }
        Relationships: [
          {
            foreignKeyName: "approval_workflows_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_workflows_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_workflows_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "approval_workflows_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["currency_code"]
          },
        ]
      }
      asset_depreciation_entries: {
        Row: {
          accumulated_depr_after: number
          asset_id: string
          company_id: string
          created_at: string
          depreciation_amount: number
          entry_date: string
          id: string
          journal_entry_id: string | null
          net_book_value_after: number
          period_number: number
          posted_at: string | null
          posted_by: string | null
          status: string
        }
        Insert: {
          accumulated_depr_after?: number
          asset_id: string
          company_id: string
          created_at?: string
          depreciation_amount: number
          entry_date: string
          id?: string
          journal_entry_id?: string | null
          net_book_value_after?: number
          period_number: number
          posted_at?: string | null
          posted_by?: string | null
          status?: string
        }
        Update: {
          accumulated_depr_after?: number
          asset_id?: string
          company_id?: string
          created_at?: string
          depreciation_amount?: number
          entry_date?: string
          id?: string
          journal_entry_id?: string | null
          net_book_value_after?: number
          period_number?: number
          posted_at?: string | null
          posted_by?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "asset_depreciation_entries_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "fixed_assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_depreciation_entries_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_depreciation_entries_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "asset_depreciation_entries_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
        ]
      }
      asset_disposals: {
        Row: {
          accum_depr_at_disposal: number
          asset_id: string
          company_id: string
          cost_at_disposal: number
          created_at: string
          created_by: string | null
          disposal_date: string
          disposal_type: string
          fiscal_period_id: string | null
          gain_loss_amount: number
          id: string
          journal_entry_id: string | null
          net_book_value: number
          notes: string | null
          proceeds_account_id: string | null
          proceeds_amount: number
        }
        Insert: {
          accum_depr_at_disposal?: number
          asset_id: string
          company_id: string
          cost_at_disposal: number
          created_at?: string
          created_by?: string | null
          disposal_date: string
          disposal_type: string
          fiscal_period_id?: string | null
          gain_loss_amount?: number
          id?: string
          journal_entry_id?: string | null
          net_book_value: number
          notes?: string | null
          proceeds_account_id?: string | null
          proceeds_amount?: number
        }
        Update: {
          accum_depr_at_disposal?: number
          asset_id?: string
          company_id?: string
          cost_at_disposal?: number
          created_at?: string
          created_by?: string | null
          disposal_date?: string
          disposal_type?: string
          fiscal_period_id?: string | null
          gain_loss_amount?: number
          id?: string
          journal_entry_id?: string | null
          net_book_value?: number
          notes?: string | null
          proceeds_account_id?: string | null
          proceeds_amount?: number
        }
        Relationships: [
          {
            foreignKeyName: "asset_disposals_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "fixed_assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_disposals_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_disposals_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "asset_disposals_fiscal_period_id_fkey"
            columns: ["fiscal_period_id"]
            isOneToOne: false
            referencedRelation: "fiscal_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_disposals_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_disposals_proceeds_account_id_fkey"
            columns: ["proceeds_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      asset_impairments: {
        Row: {
          asset_id: string
          carrying_amount_before: number
          company_id: string
          created_at: string
          created_by: string | null
          fiscal_period_id: string | null
          gl_accum_impairment_account_id: string | null
          gl_impairment_loss_account_id: string | null
          id: string
          impairment_date: string
          impairment_loss: number
          journal_entry_id: string | null
          notes: string | null
          recoverable_amount: number
        }
        Insert: {
          asset_id: string
          carrying_amount_before: number
          company_id: string
          created_at?: string
          created_by?: string | null
          fiscal_period_id?: string | null
          gl_accum_impairment_account_id?: string | null
          gl_impairment_loss_account_id?: string | null
          id?: string
          impairment_date: string
          impairment_loss: number
          journal_entry_id?: string | null
          notes?: string | null
          recoverable_amount?: number
        }
        Update: {
          asset_id?: string
          carrying_amount_before?: number
          company_id?: string
          created_at?: string
          created_by?: string | null
          fiscal_period_id?: string | null
          gl_accum_impairment_account_id?: string | null
          gl_impairment_loss_account_id?: string | null
          id?: string
          impairment_date?: string
          impairment_loss?: number
          journal_entry_id?: string | null
          notes?: string | null
          recoverable_amount?: number
        }
        Relationships: [
          {
            foreignKeyName: "asset_impairments_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "fixed_assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_impairments_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_impairments_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "asset_impairments_fiscal_period_id_fkey"
            columns: ["fiscal_period_id"]
            isOneToOne: false
            referencedRelation: "fiscal_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_impairments_gl_accum_impairment_account_id_fkey"
            columns: ["gl_accum_impairment_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_impairments_gl_impairment_loss_account_id_fkey"
            columns: ["gl_impairment_loss_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_impairments_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
        ]
      }
      asset_transfers: {
        Row: {
          asset_id: string
          company_id: string
          created_at: string
          created_by: string | null
          from_branch_id: string | null
          from_department_id: string | null
          id: string
          notes: string | null
          to_branch_id: string | null
          to_department_id: string | null
          transfer_date: string
        }
        Insert: {
          asset_id: string
          company_id: string
          created_at?: string
          created_by?: string | null
          from_branch_id?: string | null
          from_department_id?: string | null
          id?: string
          notes?: string | null
          to_branch_id?: string | null
          to_department_id?: string | null
          transfer_date: string
        }
        Update: {
          asset_id?: string
          company_id?: string
          created_at?: string
          created_by?: string | null
          from_branch_id?: string | null
          from_department_id?: string | null
          id?: string
          notes?: string | null
          to_branch_id?: string | null
          to_department_id?: string | null
          transfer_date?: string
        }
        Relationships: [
          {
            foreignKeyName: "asset_transfers_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "fixed_assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_transfers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_transfers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "asset_transfers_from_branch_id_fkey"
            columns: ["from_branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_transfers_from_department_id_fkey"
            columns: ["from_department_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_transfers_to_branch_id_fkey"
            columns: ["to_branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_transfers_to_department_id_fkey"
            columns: ["to_department_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
        ]
      }
      atc_codes: {
        Row: {
          code: string
          created_at: string | null
          created_by: string | null
          deprecated_at: string | null
          deprecated_reason: string | null
          description: string
          effective_from: string
          effective_to: string | null
          id: string
          is_active: boolean | null
          rate: number
          supersedes_atc_code_id: string | null
          tax_category: string
          updated_at: string | null
          updated_by: string | null
        }
        Insert: {
          code: string
          created_at?: string | null
          created_by?: string | null
          deprecated_at?: string | null
          deprecated_reason?: string | null
          description: string
          effective_from?: string
          effective_to?: string | null
          id?: string
          is_active?: boolean | null
          rate: number
          supersedes_atc_code_id?: string | null
          tax_category: string
          updated_at?: string | null
          updated_by?: string | null
        }
        Update: {
          code?: string
          created_at?: string | null
          created_by?: string | null
          deprecated_at?: string | null
          deprecated_reason?: string | null
          description?: string
          effective_from?: string
          effective_to?: string | null
          id?: string
          is_active?: boolean | null
          rate?: number
          supersedes_atc_code_id?: string | null
          tax_category?: string
          updated_at?: string | null
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "atc_codes_supersedes_atc_code_id_fkey"
            columns: ["supersedes_atc_code_id"]
            isOneToOne: false
            referencedRelation: "atc_codes"
            referencedColumns: ["id"]
          },
        ]
      }
      bank_accounts: {
        Row: {
          account_name: string
          account_number: string
          account_type: string
          bank_branch: string | null
          bank_id: string | null
          bank_name: string
          branch_id: string | null
          company_id: string
          created_at: string
          created_by: string | null
          currency_id: string | null
          gl_account_id: string
          id: string
          is_active: boolean
          is_primary: boolean
          notes: string | null
          opening_balance: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          account_name: string
          account_number: string
          account_type?: string
          bank_branch?: string | null
          bank_id?: string | null
          bank_name: string
          branch_id?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          currency_id?: string | null
          gl_account_id: string
          id?: string
          is_active?: boolean
          is_primary?: boolean
          notes?: string | null
          opening_balance?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          account_name?: string
          account_number?: string
          account_type?: string
          bank_branch?: string | null
          bank_id?: string | null
          bank_name?: string
          branch_id?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          currency_id?: string | null
          gl_account_id?: string
          id?: string
          is_active?: boolean
          is_primary?: boolean
          notes?: string | null
          opening_balance?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "bank_accounts_bank_id_fkey"
            columns: ["bank_id"]
            isOneToOne: false
            referencedRelation: "ref_banks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_accounts_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_accounts_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_accounts_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "bank_accounts_currency_id_fkey"
            columns: ["currency_id"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_accounts_gl_account_id_fkey"
            columns: ["gl_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      bank_adjustments: {
        Row: {
          adjustment_date: string
          adjustment_type: string
          amount: number
          ba_number: string
          bank_account_id: string
          branch_id: string | null
          company_id: string
          created_at: string
          created_by: string | null
          description: string
          fiscal_period_id: string | null
          gl_account_id: string
          id: string
          journal_entry_id: string | null
          posted_at: string | null
          posted_by: string | null
          reference_number: string | null
          status: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          adjustment_date: string
          adjustment_type: string
          amount: number
          ba_number: string
          bank_account_id: string
          branch_id?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          description: string
          fiscal_period_id?: string | null
          gl_account_id: string
          id?: string
          journal_entry_id?: string | null
          posted_at?: string | null
          posted_by?: string | null
          reference_number?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          adjustment_date?: string
          adjustment_type?: string
          amount?: number
          ba_number?: string
          bank_account_id?: string
          branch_id?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          description?: string
          fiscal_period_id?: string | null
          gl_account_id?: string
          id?: string
          journal_entry_id?: string | null
          posted_at?: string | null
          posted_by?: string | null
          reference_number?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "bank_adjustments_bank_account_id_fkey"
            columns: ["bank_account_id"]
            isOneToOne: false
            referencedRelation: "bank_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_adjustments_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_adjustments_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_adjustments_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "bank_adjustments_fiscal_period_id_fkey"
            columns: ["fiscal_period_id"]
            isOneToOne: false
            referencedRelation: "fiscal_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_adjustments_gl_account_id_fkey"
            columns: ["gl_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_adjustments_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
        ]
      }
      bank_recon_items: {
        Row: {
          amount: number
          company_id: string
          created_at: string
          created_by: string | null
          description: string
          document_date: string | null
          id: string
          item_type: string
          reconciliation_id: string
          reference_doc_id: string | null
          reference_doc_type: string | null
        }
        Insert: {
          amount: number
          company_id: string
          created_at?: string
          created_by?: string | null
          description: string
          document_date?: string | null
          id?: string
          item_type: string
          reconciliation_id: string
          reference_doc_id?: string | null
          reference_doc_type?: string | null
        }
        Update: {
          amount?: number
          company_id?: string
          created_at?: string
          created_by?: string | null
          description?: string
          document_date?: string | null
          id?: string
          item_type?: string
          reconciliation_id?: string
          reference_doc_id?: string | null
          reference_doc_type?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "bank_recon_items_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_recon_items_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "bank_recon_items_reconciliation_id_fkey"
            columns: ["reconciliation_id"]
            isOneToOne: false
            referencedRelation: "bank_reconciliations"
            referencedColumns: ["id"]
          },
        ]
      }
      bank_reconciliations: {
        Row: {
          adjusted_bank_balance: number | null
          adjusted_book_balance: number | null
          bank_account_id: string
          bank_errors: number
          bank_statement_balance: number
          book_adjustments_add: number
          book_adjustments_less: number
          book_balance: number
          book_errors: number
          branch_id: string | null
          company_id: string
          created_at: string
          created_by: string | null
          deposits_in_transit: number
          difference: number | null
          finalized_at: string | null
          finalized_by: string | null
          id: string
          outstanding_checks: number
          recon_month: number
          recon_year: number
          reconciliation_date: string
          remarks: string | null
          status: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          adjusted_bank_balance?: number | null
          adjusted_book_balance?: number | null
          bank_account_id: string
          bank_errors?: number
          bank_statement_balance?: number
          book_adjustments_add?: number
          book_adjustments_less?: number
          book_balance?: number
          book_errors?: number
          branch_id?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          deposits_in_transit?: number
          difference?: number | null
          finalized_at?: string | null
          finalized_by?: string | null
          id?: string
          outstanding_checks?: number
          recon_month: number
          recon_year: number
          reconciliation_date: string
          remarks?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          adjusted_bank_balance?: number | null
          adjusted_book_balance?: number | null
          bank_account_id?: string
          bank_errors?: number
          bank_statement_balance?: number
          book_adjustments_add?: number
          book_adjustments_less?: number
          book_balance?: number
          book_errors?: number
          branch_id?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          deposits_in_transit?: number
          difference?: number | null
          finalized_at?: string | null
          finalized_by?: string | null
          id?: string
          outstanding_checks?: number
          recon_month?: number
          recon_year?: number
          reconciliation_date?: string
          remarks?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "bank_reconciliations_bank_account_id_fkey"
            columns: ["bank_account_id"]
            isOneToOne: false
            referencedRelation: "bank_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_reconciliations_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_reconciliations_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_reconciliations_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      bir_config_maintainers: {
        Row: {
          granted_at: string | null
          granted_by: string | null
          note: string | null
          user_id: string
        }
        Insert: {
          granted_at?: string | null
          granted_by?: string | null
          note?: string | null
          user_id: string
        }
        Update: {
          granted_at?: string | null
          granted_by?: string | null
          note?: string | null
          user_id?: string
        }
        Relationships: []
      }
      bir_form_mappings: {
        Row: {
          created_at: string | null
          created_by: string | null
          form_id: string
          id: string
          line_identifier: string
          source_id: string | null
          source_type: string
          updated_at: string | null
          updated_by: string | null
        }
        Insert: {
          created_at?: string | null
          created_by?: string | null
          form_id: string
          id?: string
          line_identifier: string
          source_id?: string | null
          source_type: string
          updated_at?: string | null
          updated_by?: string | null
        }
        Update: {
          created_at?: string | null
          created_by?: string | null
          form_id?: string
          id?: string
          line_identifier?: string
          source_id?: string | null
          source_type?: string
          updated_at?: string | null
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "bir_form_mappings_form_id_fkey"
            columns: ["form_id"]
            isOneToOne: false
            referencedRelation: "bir_forms"
            referencedColumns: ["id"]
          },
        ]
      }
      bir_forms: {
        Row: {
          created_at: string | null
          created_by: string | null
          description: string
          form_number: string
          frequency: string
          id: string
          is_active: boolean | null
          updated_at: string | null
          updated_by: string | null
        }
        Insert: {
          created_at?: string | null
          created_by?: string | null
          description: string
          form_number: string
          frequency: string
          id?: string
          is_active?: boolean | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Update: {
          created_at?: string | null
          created_by?: string | null
          description?: string
          form_number?: string
          frequency?: string
          id?: string
          is_active?: boolean | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Relationships: []
      }
      book_tax_reconciliation: {
        Row: {
          addback_nondeductible: number
          book_income: number
          company_id: string
          created_at: string
          created_by: string | null
          deduct_nontaxable: number
          id: string
          period_quarter: number | null
          period_type: string
          period_year: number
          remarks: string | null
          status: string
          taxable_income: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          addback_nondeductible?: number
          book_income?: number
          company_id: string
          created_at?: string
          created_by?: string | null
          deduct_nontaxable?: number
          id?: string
          period_quarter?: number | null
          period_type: string
          period_year: number
          remarks?: string | null
          status?: string
          taxable_income?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          addback_nondeductible?: number
          book_income?: number
          company_id?: string
          created_at?: string
          created_by?: string | null
          deduct_nontaxable?: number
          id?: string
          period_quarter?: number | null
          period_type?: string
          period_year?: number
          remarks?: string | null
          status?: string
          taxable_income?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "book_tax_reconciliation_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "book_tax_reconciliation_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      branches: {
        Row: {
          address_line_1: string
          address_line_2: string
          bir_reg_date: string | null
          branch_code: string
          branch_manager: string | null
          branch_name: string
          branch_type: string
          cas_date_issued: string | null
          cas_permit_no: string | null
          city: string
          company_id: string
          created_at: string | null
          created_by: string | null
          email: string | null
          id: string
          is_active: boolean | null
          lgu_permit_number: string | null
          lgu_reg_date: string | null
          mobile_number: string | null
          phone_number: string | null
          province: string
          rdo_id: string | null
          tax_registration_override: string
          tin_branch_code: string
          updated_at: string | null
          updated_by: string | null
          zip_code: string
        }
        Insert: {
          address_line_1: string
          address_line_2: string
          bir_reg_date?: string | null
          branch_code: string
          branch_manager?: string | null
          branch_name: string
          branch_type?: string
          cas_date_issued?: string | null
          cas_permit_no?: string | null
          city: string
          company_id: string
          created_at?: string | null
          created_by?: string | null
          email?: string | null
          id?: string
          is_active?: boolean | null
          lgu_permit_number?: string | null
          lgu_reg_date?: string | null
          mobile_number?: string | null
          phone_number?: string | null
          province: string
          rdo_id?: string | null
          tax_registration_override?: string
          tin_branch_code?: string
          updated_at?: string | null
          updated_by?: string | null
          zip_code: string
        }
        Update: {
          address_line_1?: string
          address_line_2?: string
          bir_reg_date?: string | null
          branch_code?: string
          branch_manager?: string | null
          branch_name?: string
          branch_type?: string
          cas_date_issued?: string | null
          cas_permit_no?: string | null
          city?: string
          company_id?: string
          created_at?: string | null
          created_by?: string | null
          email?: string | null
          id?: string
          is_active?: boolean | null
          lgu_permit_number?: string | null
          lgu_reg_date?: string | null
          mobile_number?: string | null
          phone_number?: string | null
          province?: string
          rdo_id?: string | null
          tax_registration_override?: string
          tin_branch_code?: string
          updated_at?: string | null
          updated_by?: string | null
          zip_code?: string
        }
        Relationships: [
          {
            foreignKeyName: "branches_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "branches_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "branches_rdo_id_fkey"
            columns: ["rdo_id"]
            isOneToOne: false
            referencedRelation: "ref_rdo_codes"
            referencedColumns: ["id"]
          },
        ]
      }
      cas_attachment_register: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          description: string | null
          document_type: string
          file_name: string
          id: string
          reference_no: string | null
          remarks: string | null
          source_doc_ref: string | null
          source_doc_type: string | null
          updated_at: string
          updated_by: string | null
          uploaded_at: string
          uploaded_by: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          document_type: string
          file_name: string
          id?: string
          reference_no?: string | null
          remarks?: string | null
          source_doc_ref?: string | null
          source_doc_type?: string | null
          updated_at?: string
          updated_by?: string | null
          uploaded_at?: string
          uploaded_by?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          document_type?: string
          file_name?: string
          id?: string
          reference_no?: string | null
          remarks?: string | null
          source_doc_ref?: string | null
          source_doc_type?: string | null
          updated_at?: string
          updated_by?: string | null
          uploaded_at?: string
          uploaded_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "cas_attachment_register_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cas_attachment_register_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      cas_document_number_issuances: {
        Row: {
          allocated_at: string
          allocated_by: string | null
          branch_id: string | null
          company_id: string
          document_code: string
          document_number: string
          id: string
          issued_at: string | null
          number_series_id: string | null
          sequence_number: number | null
          source_id: string | null
          source_table: string | null
          status: string
          void_reason: string | null
          voided_at: string | null
        }
        Insert: {
          allocated_at?: string
          allocated_by?: string | null
          branch_id?: string | null
          company_id: string
          document_code: string
          document_number: string
          id?: string
          issued_at?: string | null
          number_series_id?: string | null
          sequence_number?: number | null
          source_id?: string | null
          source_table?: string | null
          status?: string
          void_reason?: string | null
          voided_at?: string | null
        }
        Update: {
          allocated_at?: string
          allocated_by?: string | null
          branch_id?: string | null
          company_id?: string
          document_code?: string
          document_number?: string
          id?: string
          issued_at?: string | null
          number_series_id?: string | null
          sequence_number?: number | null
          source_id?: string | null
          source_table?: string | null
          status?: string
          void_reason?: string | null
          voided_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "cas_document_number_issuances_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cas_document_number_issuances_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cas_document_number_issuances_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "cas_document_number_issuances_number_series_id_fkey"
            columns: ["number_series_id"]
            isOneToOne: false
            referencedRelation: "number_series"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cas_document_number_issuances_number_series_id_fkey"
            columns: ["number_series_id"]
            isOneToOne: false
            referencedRelation: "vw_cas_atp_usage"
            referencedColumns: ["number_series_id"]
          },
        ]
      }
      cas_document_void_events: {
        Row: {
          branch_id: string | null
          company_id: string
          document_amount: number | null
          document_code: string
          document_date: string | null
          document_number: string
          event_actor_id: string | null
          id: string
          number_issuance_id: string | null
          occurred_at: string
          original_journal_entry_id: string | null
          party_id: string | null
          party_name: string | null
          party_tin: string | null
          party_type: string | null
          reason_code_id: string | null
          reason_text: string
          reversal_journal_entry_id: string | null
          source_id: string
          source_snapshot: Json
          source_table: string
          terminal_status: string
        }
        Insert: {
          branch_id?: string | null
          company_id: string
          document_amount?: number | null
          document_code: string
          document_date?: string | null
          document_number: string
          event_actor_id?: string | null
          id?: string
          number_issuance_id?: string | null
          occurred_at?: string
          original_journal_entry_id?: string | null
          party_id?: string | null
          party_name?: string | null
          party_tin?: string | null
          party_type?: string | null
          reason_code_id?: string | null
          reason_text: string
          reversal_journal_entry_id?: string | null
          source_id: string
          source_snapshot: Json
          source_table: string
          terminal_status: string
        }
        Update: {
          branch_id?: string | null
          company_id?: string
          document_amount?: number | null
          document_code?: string
          document_date?: string | null
          document_number?: string
          event_actor_id?: string | null
          id?: string
          number_issuance_id?: string | null
          occurred_at?: string
          original_journal_entry_id?: string | null
          party_id?: string | null
          party_name?: string | null
          party_tin?: string | null
          party_type?: string | null
          reason_code_id?: string | null
          reason_text?: string
          reversal_journal_entry_id?: string | null
          source_id?: string
          source_snapshot?: Json
          source_table?: string
          terminal_status?: string
        }
        Relationships: [
          {
            foreignKeyName: "cas_document_void_events_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cas_document_void_events_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cas_document_void_events_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "cas_document_void_events_number_issuance_id_fkey"
            columns: ["number_issuance_id"]
            isOneToOne: false
            referencedRelation: "cas_document_number_issuances"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cas_document_void_events_original_journal_entry_id_fkey"
            columns: ["original_journal_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cas_document_void_events_reason_code_id_fkey"
            columns: ["reason_code_id"]
            isOneToOne: false
            referencedRelation: "void_reason_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cas_document_void_events_reversal_journal_entry_id_fkey"
            columns: ["reversal_journal_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
        ]
      }
      cas_export_artifacts: {
        Row: {
          byte_count: number
          company_id: string
          encoding: string
          file_content: string
          file_hash: string
          file_name: string
          generated_at: string
          generated_by: string | null
          id: string
          layout_version: string
          mime_type: string
          newline_style: string
          snapshot_id: string
        }
        Insert: {
          byte_count: number
          company_id: string
          encoding?: string
          file_content: string
          file_hash: string
          file_name: string
          generated_at?: string
          generated_by?: string | null
          id?: string
          layout_version: string
          mime_type?: string
          newline_style?: string
          snapshot_id: string
        }
        Update: {
          byte_count?: number
          company_id?: string
          encoding?: string
          file_content?: string
          file_hash?: string
          file_name?: string
          generated_at?: string
          generated_by?: string | null
          id?: string
          layout_version?: string
          mime_type?: string
          newline_style?: string
          snapshot_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "cas_export_artifacts_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cas_export_artifacts_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "cas_export_artifacts_snapshot_id_fkey"
            columns: ["snapshot_id"]
            isOneToOne: true
            referencedRelation: "report_snapshots"
            referencedColumns: ["id"]
          },
        ]
      }
      cas_export_log: {
        Row: {
          artifact_id: string | null
          company_id: string
          export_type: string
          file_hash: string | null
          file_name: string
          file_sha256: string | null
          file_size_bytes: number | null
          generated_at: string
          generated_by: string | null
          id: string
          layout_version: string | null
          period_month: number | null
          period_quarter: number | null
          period_year: number | null
          remarks: string | null
          report_name: string
          row_count: number
          snapshot_id: string | null
        }
        Insert: {
          artifact_id?: string | null
          company_id: string
          export_type: string
          file_hash?: string | null
          file_name: string
          file_sha256?: string | null
          file_size_bytes?: number | null
          generated_at?: string
          generated_by?: string | null
          id?: string
          layout_version?: string | null
          period_month?: number | null
          period_quarter?: number | null
          period_year?: number | null
          remarks?: string | null
          report_name: string
          row_count?: number
          snapshot_id?: string | null
        }
        Update: {
          artifact_id?: string | null
          company_id?: string
          export_type?: string
          file_hash?: string | null
          file_name?: string
          file_sha256?: string | null
          file_size_bytes?: number | null
          generated_at?: string
          generated_by?: string | null
          id?: string
          layout_version?: string | null
          period_month?: number | null
          period_quarter?: number | null
          period_year?: number | null
          remarks?: string | null
          report_name?: string
          row_count?: number
          snapshot_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "cas_export_log_artifact_id_fkey"
            columns: ["artifact_id"]
            isOneToOne: false
            referencedRelation: "cas_export_artifacts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cas_export_log_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cas_export_log_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "cas_export_log_snapshot_id_fkey"
            columns: ["snapshot_id"]
            isOneToOne: false
            referencedRelation: "report_snapshots"
            referencedColumns: ["id"]
          },
        ]
      }
      cash_count_sheets: {
        Row: {
          book_balance: number
          branch_id: string | null
          coins_and_bills: number
          company_id: string
          count_date: string
          counted_amount: number
          counted_by: string
          created_at: string
          created_by: string | null
          fund_id: string
          id: string
          other_items: number
          remarks: string | null
          sheet_number: string
          shortage_overage: number | null
          status: string
          unreplenished_pcvs: number
          updated_at: string
          updated_by: string | null
          witnessed_by: string | null
        }
        Insert: {
          book_balance?: number
          branch_id?: string | null
          coins_and_bills?: number
          company_id: string
          count_date: string
          counted_amount?: number
          counted_by: string
          created_at?: string
          created_by?: string | null
          fund_id: string
          id?: string
          other_items?: number
          remarks?: string | null
          sheet_number: string
          shortage_overage?: number | null
          status?: string
          unreplenished_pcvs?: number
          updated_at?: string
          updated_by?: string | null
          witnessed_by?: string | null
        }
        Update: {
          book_balance?: number
          branch_id?: string | null
          coins_and_bills?: number
          company_id?: string
          count_date?: string
          counted_amount?: number
          counted_by?: string
          created_at?: string
          created_by?: string | null
          fund_id?: string
          id?: string
          other_items?: number
          remarks?: string | null
          sheet_number?: string
          shortage_overage?: number | null
          status?: string
          unreplenished_pcvs?: number
          updated_at?: string
          updated_by?: string | null
          witnessed_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "cash_count_sheets_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_count_sheets_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_count_sheets_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "cash_count_sheets_fund_id_fkey"
            columns: ["fund_id"]
            isOneToOne: false
            referencedRelation: "petty_cash_funds"
            referencedColumns: ["id"]
          },
        ]
      }
      cash_purchase_lines: {
        Row: {
          company_id: string
          cp_id: string
          created_at: string
          created_by: string | null
          description: string
          ewt_amount: number
          ewt_atc_code_id: string | null
          ewt_income_nature: string | null
          ewt_tax_base: number | null
          ewt_variance_reason: string | null
          expense_account_id: string | null
          id: string
          input_vat_amount: number
          inventory_transaction_id: string | null
          item_id: string | null
          line_number: number
          lot_number: string | null
          net_amount: number
          quantity: number
          serial_number: string | null
          total_amount: number
          unit_price: number
          uom_id: string | null
          updated_at: string
          updated_by: string | null
          vat_code_id: string | null
          warehouse_id: string | null
        }
        Insert: {
          company_id: string
          cp_id: string
          created_at?: string
          created_by?: string | null
          description: string
          ewt_amount?: number
          ewt_atc_code_id?: string | null
          ewt_income_nature?: string | null
          ewt_tax_base?: number | null
          ewt_variance_reason?: string | null
          expense_account_id?: string | null
          id?: string
          input_vat_amount?: number
          inventory_transaction_id?: string | null
          item_id?: string | null
          line_number: number
          lot_number?: string | null
          net_amount?: number
          quantity?: number
          serial_number?: string | null
          total_amount?: number
          unit_price?: number
          uom_id?: string | null
          updated_at?: string
          updated_by?: string | null
          vat_code_id?: string | null
          warehouse_id?: string | null
        }
        Update: {
          company_id?: string
          cp_id?: string
          created_at?: string
          created_by?: string | null
          description?: string
          ewt_amount?: number
          ewt_atc_code_id?: string | null
          ewt_income_nature?: string | null
          ewt_tax_base?: number | null
          ewt_variance_reason?: string | null
          expense_account_id?: string | null
          id?: string
          input_vat_amount?: number
          inventory_transaction_id?: string | null
          item_id?: string | null
          line_number?: number
          lot_number?: string | null
          net_amount?: number
          quantity?: number
          serial_number?: string | null
          total_amount?: number
          unit_price?: number
          uom_id?: string | null
          updated_at?: string
          updated_by?: string | null
          vat_code_id?: string | null
          warehouse_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "cash_purchase_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_purchase_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "cash_purchase_lines_cp_id_fkey"
            columns: ["cp_id"]
            isOneToOne: false
            referencedRelation: "cash_purchases"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_purchase_lines_ewt_atc_code_id_fkey"
            columns: ["ewt_atc_code_id"]
            isOneToOne: false
            referencedRelation: "atc_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_purchase_lines_expense_account_id_fkey"
            columns: ["expense_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_purchase_lines_inventory_transaction_id_fkey"
            columns: ["inventory_transaction_id"]
            isOneToOne: false
            referencedRelation: "inventory_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_purchase_lines_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_purchase_lines_uom_id_fkey"
            columns: ["uom_id"]
            isOneToOne: false
            referencedRelation: "units_of_measure"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_purchase_lines_vat_code_id_fkey"
            columns: ["vat_code_id"]
            isOneToOne: false
            referencedRelation: "vat_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_purchase_lines_warehouse_id_fkey"
            columns: ["warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
        ]
      }
      cash_purchases: {
        Row: {
          branch_id: string | null
          company_id: string
          cost_center_id: string | null
          cp_number: string
          created_at: string
          created_by: string | null
          department_id: string | null
          fiscal_period_id: string | null
          functional_entity_id: string | null
          id: string
          journal_entry_id: string | null
          location_id: string | null
          payment_account_id: string | null
          payment_method: string
          posted_at: string | null
          posted_by: string | null
          project_id: string | null
          reference_number: string | null
          remarks: string | null
          status: string
          supplier_id: string | null
          supplier_name_snapshot: string | null
          supplier_tin_snapshot: string | null
          total_amount: number
          total_ewt_amount: number
          total_exempt_amount: number
          total_input_vat_amount: number
          total_taxable_amount: number
          total_zero_rated_amount: number
          transaction_date: string
          updated_at: string
          updated_by: string | null
          warehouse_id: string | null
        }
        Insert: {
          branch_id?: string | null
          company_id: string
          cost_center_id?: string | null
          cp_number: string
          created_at?: string
          created_by?: string | null
          department_id?: string | null
          fiscal_period_id?: string | null
          functional_entity_id?: string | null
          id?: string
          journal_entry_id?: string | null
          location_id?: string | null
          payment_account_id?: string | null
          payment_method?: string
          posted_at?: string | null
          posted_by?: string | null
          project_id?: string | null
          reference_number?: string | null
          remarks?: string | null
          status?: string
          supplier_id?: string | null
          supplier_name_snapshot?: string | null
          supplier_tin_snapshot?: string | null
          total_amount?: number
          total_ewt_amount?: number
          total_exempt_amount?: number
          total_input_vat_amount?: number
          total_taxable_amount?: number
          total_zero_rated_amount?: number
          transaction_date: string
          updated_at?: string
          updated_by?: string | null
          warehouse_id?: string | null
        }
        Update: {
          branch_id?: string | null
          company_id?: string
          cost_center_id?: string | null
          cp_number?: string
          created_at?: string
          created_by?: string | null
          department_id?: string | null
          fiscal_period_id?: string | null
          functional_entity_id?: string | null
          id?: string
          journal_entry_id?: string | null
          location_id?: string | null
          payment_account_id?: string | null
          payment_method?: string
          posted_at?: string | null
          posted_by?: string | null
          project_id?: string | null
          reference_number?: string | null
          remarks?: string | null
          status?: string
          supplier_id?: string | null
          supplier_name_snapshot?: string | null
          supplier_tin_snapshot?: string | null
          total_amount?: number
          total_ewt_amount?: number
          total_exempt_amount?: number
          total_input_vat_amount?: number
          total_taxable_amount?: number
          total_zero_rated_amount?: number
          transaction_date?: string
          updated_at?: string
          updated_by?: string | null
          warehouse_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "cash_purchases_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_purchases_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_purchases_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "cash_purchases_cost_center_id_fkey"
            columns: ["cost_center_id"]
            isOneToOne: false
            referencedRelation: "cost_centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_purchases_department_id_fkey"
            columns: ["department_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_purchases_fiscal_period_id_fkey"
            columns: ["fiscal_period_id"]
            isOneToOne: false
            referencedRelation: "fiscal_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_purchases_functional_entity_id_fkey"
            columns: ["functional_entity_id"]
            isOneToOne: false
            referencedRelation: "functional_entities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_purchases_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_purchases_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_purchases_payment_account_id_fkey"
            columns: ["payment_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_purchases_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_purchases_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_purchases_warehouse_id_fkey"
            columns: ["warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
        ]
      }
      chart_of_accounts: {
        Row: {
          account_code: string
          account_name: string
          account_type: string
          allow_subledger: boolean
          cash_flow_category: string | null
          company_id: string
          cost_behavior: string | null
          created_at: string | null
          created_by: string | null
          currency_code: string | null
          effective_from: string | null
          effective_to: string | null
          fs_group: string | null
          fs_statement: string | null
          fs_subgroup: string | null
          id: string
          is_active: boolean | null
          is_capitalizable: boolean
          is_cash_equivalent: boolean
          is_control_account: boolean
          is_operating_expense: boolean
          is_postable: boolean | null
          is_tax_account: boolean
          lifecycle_status: string
          normal_balance: string
          parent_id: string | null
          subledger_type: string | null
          updated_at: string | null
          updated_by: string | null
        }
        Insert: {
          account_code: string
          account_name: string
          account_type: string
          allow_subledger?: boolean
          cash_flow_category?: string | null
          company_id: string
          cost_behavior?: string | null
          created_at?: string | null
          created_by?: string | null
          currency_code?: string | null
          effective_from?: string | null
          effective_to?: string | null
          fs_group?: string | null
          fs_statement?: string | null
          fs_subgroup?: string | null
          id?: string
          is_active?: boolean | null
          is_capitalizable?: boolean
          is_cash_equivalent?: boolean
          is_control_account?: boolean
          is_operating_expense?: boolean
          is_postable?: boolean | null
          is_tax_account?: boolean
          lifecycle_status?: string
          normal_balance: string
          parent_id?: string | null
          subledger_type?: string | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Update: {
          account_code?: string
          account_name?: string
          account_type?: string
          allow_subledger?: boolean
          cash_flow_category?: string | null
          company_id?: string
          cost_behavior?: string | null
          created_at?: string | null
          created_by?: string | null
          currency_code?: string | null
          effective_from?: string | null
          effective_to?: string | null
          fs_group?: string | null
          fs_statement?: string | null
          fs_subgroup?: string | null
          id?: string
          is_active?: boolean | null
          is_capitalizable?: boolean
          is_cash_equivalent?: boolean
          is_control_account?: boolean
          is_operating_expense?: boolean
          is_postable?: boolean | null
          is_tax_account?: boolean
          lifecycle_status?: string
          normal_balance?: string
          parent_id?: string | null
          subledger_type?: string | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "chart_of_accounts_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chart_of_accounts_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "chart_of_accounts_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      check_voucher_lines: {
        Row: {
          amount: number
          company_id: string
          created_at: string
          created_by: string | null
          cv_id: string
          description: string
          expense_account_id: string
          id: string
          line_number: number
          updated_by: string | null
        }
        Insert: {
          amount: number
          company_id: string
          created_at?: string
          created_by?: string | null
          cv_id: string
          description: string
          expense_account_id: string
          id?: string
          line_number: number
          updated_by?: string | null
        }
        Update: {
          amount?: number
          company_id?: string
          created_at?: string
          created_by?: string | null
          cv_id?: string
          description?: string
          expense_account_id?: string
          id?: string
          line_number?: number
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "check_voucher_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "check_voucher_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "check_voucher_lines_cv_id_fkey"
            columns: ["cv_id"]
            isOneToOne: false
            referencedRelation: "check_vouchers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "check_voucher_lines_cv_id_fkey"
            columns: ["cv_id"]
            isOneToOne: false
            referencedRelation: "vw_outstanding_checks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "check_voucher_lines_expense_account_id_fkey"
            columns: ["expense_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      check_vouchers: {
        Row: {
          atc_code_id: string | null
          bank_account_id: string
          branch_id: string | null
          check_date: string
          check_number: string
          cleared_date: string | null
          company_id: string
          created_at: string
          created_by: string | null
          cv_number: string
          ewt_rate: number | null
          ewt_tax_base: number | null
          ewt_variance_reason: string | null
          fiscal_period_id: string | null
          id: string
          journal_entry_id: string | null
          net_check_amount: number | null
          particulars: string
          payee: string
          payee_tin: string | null
          posted_at: string | null
          posted_by: string | null
          stale_date: string | null
          status: string
          supplier_id: string | null
          total_ewt_amount: number
          total_gross_amount: number
          updated_at: string
          updated_by: string | null
          voucher_date: string
        }
        Insert: {
          atc_code_id?: string | null
          bank_account_id: string
          branch_id?: string | null
          check_date: string
          check_number: string
          cleared_date?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          cv_number: string
          ewt_rate?: number | null
          ewt_tax_base?: number | null
          ewt_variance_reason?: string | null
          fiscal_period_id?: string | null
          id?: string
          journal_entry_id?: string | null
          net_check_amount?: number | null
          particulars: string
          payee: string
          payee_tin?: string | null
          posted_at?: string | null
          posted_by?: string | null
          stale_date?: string | null
          status?: string
          supplier_id?: string | null
          total_ewt_amount?: number
          total_gross_amount?: number
          updated_at?: string
          updated_by?: string | null
          voucher_date: string
        }
        Update: {
          atc_code_id?: string | null
          bank_account_id?: string
          branch_id?: string | null
          check_date?: string
          check_number?: string
          cleared_date?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          cv_number?: string
          ewt_rate?: number | null
          ewt_tax_base?: number | null
          ewt_variance_reason?: string | null
          fiscal_period_id?: string | null
          id?: string
          journal_entry_id?: string | null
          net_check_amount?: number | null
          particulars?: string
          payee?: string
          payee_tin?: string | null
          posted_at?: string | null
          posted_by?: string | null
          stale_date?: string | null
          status?: string
          supplier_id?: string | null
          total_ewt_amount?: number
          total_gross_amount?: number
          updated_at?: string
          updated_by?: string | null
          voucher_date?: string
        }
        Relationships: [
          {
            foreignKeyName: "check_vouchers_atc_code_id_fkey"
            columns: ["atc_code_id"]
            isOneToOne: false
            referencedRelation: "atc_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "check_vouchers_bank_account_id_fkey"
            columns: ["bank_account_id"]
            isOneToOne: false
            referencedRelation: "bank_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "check_vouchers_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "check_vouchers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "check_vouchers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "check_vouchers_fiscal_period_id_fkey"
            columns: ["fiscal_period_id"]
            isOneToOne: false
            referencedRelation: "fiscal_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "check_vouchers_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "check_vouchers_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
      coa_template_lines: {
        Row: {
          account_code: string
          account_name: string
          account_type: string
          allow_subledger: boolean
          cash_flow_category: string | null
          fs_group: string | null
          fs_subgroup: string | null
          id: string
          is_cash_equivalent: boolean
          is_control_account: boolean
          is_postable: boolean
          is_tax_account: boolean
          normal_balance: string
          parent_account_code: string | null
          sort_order: number
          subledger_type: string | null
          template_id: string
        }
        Insert: {
          account_code: string
          account_name: string
          account_type: string
          allow_subledger?: boolean
          cash_flow_category?: string | null
          fs_group?: string | null
          fs_subgroup?: string | null
          id?: string
          is_cash_equivalent?: boolean
          is_control_account?: boolean
          is_postable?: boolean
          is_tax_account?: boolean
          normal_balance: string
          parent_account_code?: string | null
          sort_order?: number
          subledger_type?: string | null
          template_id: string
        }
        Update: {
          account_code?: string
          account_name?: string
          account_type?: string
          allow_subledger?: boolean
          cash_flow_category?: string | null
          fs_group?: string | null
          fs_subgroup?: string | null
          id?: string
          is_cash_equivalent?: boolean
          is_control_account?: boolean
          is_postable?: boolean
          is_tax_account?: boolean
          normal_balance?: string
          parent_account_code?: string | null
          sort_order?: number
          subledger_type?: string | null
          template_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "coa_template_lines_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "coa_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      coa_templates: {
        Row: {
          created_at: string
          description: string | null
          entity_types: string[]
          id: string
          is_active: boolean
          name: string
          template_code: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          entity_types?: string[]
          id?: string
          is_active?: boolean
          name: string
          template_code: string
        }
        Update: {
          created_at?: string
          description?: string | null
          entity_types?: string[]
          id?: string
          is_active?: boolean
          name?: string
          template_code?: string
        }
        Relationships: []
      }
      companies: {
        Row: {
          accounting_period: string
          address_line_1: string
          address_line_2: string
          ap_ewt_recognition_policy: string
          bir_reg_date: string | null
          cas_date_issued: string | null
          cas_permit_no: string | null
          city: string
          company_code: string | null
          created_at: string | null
          created_by: string | null
          email: string
          entity_type: string
          fiscal_start_month: number | null
          functional_currency_code: string
          id: string
          is_active: boolean | null
          lgu_reg_date: string | null
          line_of_business: string
          logo_url: string | null
          mobile_number: string | null
          parent_company_id: string | null
          phone_number: string | null
          province: string
          psic_code: string | null
          rdo_id: string | null
          registered_name: string
          registration_number: string | null
          reporting_currency_code: string
          sec_dti_reg_date: string | null
          signatory_name: string
          signatory_position: string
          signatory_tin: string | null
          tax_registration: string
          tin: string
          trade_name: string | null
          updated_at: string | null
          updated_by: string | null
          workspace_accent_color: string
          zip_code: string
        }
        Insert: {
          accounting_period: string
          address_line_1: string
          address_line_2: string
          ap_ewt_recognition_policy?: string
          bir_reg_date?: string | null
          cas_date_issued?: string | null
          cas_permit_no?: string | null
          city: string
          company_code?: string | null
          created_at?: string | null
          created_by?: string | null
          email: string
          entity_type: string
          fiscal_start_month?: number | null
          functional_currency_code?: string
          id?: string
          is_active?: boolean | null
          lgu_reg_date?: string | null
          line_of_business: string
          logo_url?: string | null
          mobile_number?: string | null
          parent_company_id?: string | null
          phone_number?: string | null
          province: string
          psic_code?: string | null
          rdo_id?: string | null
          registered_name: string
          registration_number?: string | null
          reporting_currency_code?: string
          sec_dti_reg_date?: string | null
          signatory_name: string
          signatory_position: string
          signatory_tin?: string | null
          tax_registration: string
          tin: string
          trade_name?: string | null
          updated_at?: string | null
          updated_by?: string | null
          workspace_accent_color?: string
          zip_code: string
        }
        Update: {
          accounting_period?: string
          address_line_1?: string
          address_line_2?: string
          ap_ewt_recognition_policy?: string
          bir_reg_date?: string | null
          cas_date_issued?: string | null
          cas_permit_no?: string | null
          city?: string
          company_code?: string | null
          created_at?: string | null
          created_by?: string | null
          email?: string
          entity_type?: string
          fiscal_start_month?: number | null
          functional_currency_code?: string
          id?: string
          is_active?: boolean | null
          lgu_reg_date?: string | null
          line_of_business?: string
          logo_url?: string | null
          mobile_number?: string | null
          parent_company_id?: string | null
          phone_number?: string | null
          province?: string
          psic_code?: string | null
          rdo_id?: string | null
          registered_name?: string
          registration_number?: string | null
          reporting_currency_code?: string
          sec_dti_reg_date?: string | null
          signatory_name?: string
          signatory_position?: string
          signatory_tin?: string | null
          tax_registration?: string
          tin?: string
          trade_name?: string | null
          updated_at?: string | null
          updated_by?: string | null
          workspace_accent_color?: string
          zip_code?: string
        }
        Relationships: [
          {
            foreignKeyName: "companies_functional_currency_code_fkey"
            columns: ["functional_currency_code"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "companies_parent_company_id_fkey"
            columns: ["parent_company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "companies_parent_company_id_fkey"
            columns: ["parent_company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "companies_rdo_id_fkey"
            columns: ["rdo_id"]
            isOneToOne: false
            referencedRelation: "ref_rdo_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "companies_reporting_currency_code_fkey"
            columns: ["reporting_currency_code"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["currency_code"]
          },
        ]
      }
      company_accounting_config: {
        Row: {
          ap_account_id: string | null
          ar_account_id: string | null
          company_id: string
          created_at: string
          created_by: string | null
          customer_advances_account_id: string | null
          default_cash_account_id: string | null
          ewt_payable_account_id: string | null
          ewt_withheld_account_id: string | null
          id: string
          input_vat_account_id: string | null
          inventory_account_id: string | null
          percentage_tax_expense_account_id: string | null
          percentage_tax_payable_account_id: string | null
          purchase_clearing_account_id: string | null
          sales_delivery_clearing_account_id: string | null
          supplier_down_payments_account_id: string | null
          updated_at: string
          updated_by: string | null
          vat_payable_account_id: string | null
        }
        Insert: {
          ap_account_id?: string | null
          ar_account_id?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          customer_advances_account_id?: string | null
          default_cash_account_id?: string | null
          ewt_payable_account_id?: string | null
          ewt_withheld_account_id?: string | null
          id?: string
          input_vat_account_id?: string | null
          inventory_account_id?: string | null
          percentage_tax_expense_account_id?: string | null
          percentage_tax_payable_account_id?: string | null
          purchase_clearing_account_id?: string | null
          sales_delivery_clearing_account_id?: string | null
          supplier_down_payments_account_id?: string | null
          updated_at?: string
          updated_by?: string | null
          vat_payable_account_id?: string | null
        }
        Update: {
          ap_account_id?: string | null
          ar_account_id?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          customer_advances_account_id?: string | null
          default_cash_account_id?: string | null
          ewt_payable_account_id?: string | null
          ewt_withheld_account_id?: string | null
          id?: string
          input_vat_account_id?: string | null
          inventory_account_id?: string | null
          percentage_tax_expense_account_id?: string | null
          percentage_tax_payable_account_id?: string | null
          purchase_clearing_account_id?: string | null
          sales_delivery_clearing_account_id?: string | null
          supplier_down_payments_account_id?: string | null
          updated_at?: string
          updated_by?: string | null
          vat_payable_account_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "company_accounting_config_ap_account_id_fkey"
            columns: ["ap_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_accounting_config_ar_account_id_fkey"
            columns: ["ar_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_accounting_config_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: true
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_accounting_config_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: true
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "company_accounting_config_customer_advances_account_id_fkey"
            columns: ["customer_advances_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_accounting_config_default_cash_account_id_fkey"
            columns: ["default_cash_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_accounting_config_ewt_payable_account_id_fkey"
            columns: ["ewt_payable_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_accounting_config_ewt_withheld_account_id_fkey"
            columns: ["ewt_withheld_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_accounting_config_input_vat_account_id_fkey"
            columns: ["input_vat_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_accounting_config_inventory_account_id_fkey"
            columns: ["inventory_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_accounting_config_percentage_tax_expense_account_i_fkey"
            columns: ["percentage_tax_expense_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_accounting_config_percentage_tax_payable_account_i_fkey"
            columns: ["percentage_tax_payable_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_accounting_config_purchase_clearing_account_id_fkey"
            columns: ["purchase_clearing_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_accounting_config_sales_delivery_clearing_account__fkey"
            columns: ["sales_delivery_clearing_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_accounting_config_supplier_down_payments_account_i_fkey"
            columns: ["supplier_down_payments_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_accounting_config_vat_payable_account_id_fkey"
            columns: ["vat_payable_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      company_inventory_config: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          default_costing_method: string
          default_warehouse_id: string | null
          id: string
          negative_stock_policy: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          default_costing_method?: string
          default_warehouse_id?: string | null
          id?: string
          negative_stock_policy?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          default_costing_method?: string
          default_warehouse_id?: string | null
          id?: string
          negative_stock_policy?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "company_inventory_config_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: true
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_inventory_config_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: true
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "company_inventory_config_default_warehouse_id_fkey"
            columns: ["default_warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
        ]
      }
      company_payment_modes: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          description: string | null
          gl_account_id: string
          id: string
          is_active: boolean
          payment_mode_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          gl_account_id: string
          id?: string
          is_active?: boolean
          payment_mode_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          gl_account_id?: string
          id?: string
          is_active?: boolean
          payment_mode_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "company_payment_modes_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_payment_modes_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "company_payment_modes_gl_account_id_fkey"
            columns: ["gl_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_payment_modes_payment_mode_id_fkey"
            columns: ["payment_mode_id"]
            isOneToOne: false
            referencedRelation: "ref_payment_modes"
            referencedColumns: ["id"]
          },
        ]
      }
      company_provisioning_modules: {
        Row: {
          created_at: string
          execution_order: number
          handler_function: string
          handler_schema: string
          is_active: boolean
          module_code: string
          module_name: string
          notes: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          execution_order: number
          handler_function: string
          handler_schema?: string
          is_active?: boolean
          module_code: string
          module_name: string
          notes?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          execution_order?: number
          handler_function?: string
          handler_schema?: string
          is_active?: boolean
          module_code?: string
          module_name?: string
          notes?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      company_provisioning_runs: {
        Row: {
          company_id: string | null
          completed_at: string | null
          created_at: string
          error_code: string | null
          error_detail: string | null
          id: string
          idempotency_key: string
          module_results: Json
          request_actor: string
          request_hash: string
          requested_by: string | null
          requested_company_code: string | null
          result: Json | null
          started_at: string
          status: string
          template_code: string
          template_id: string | null
          template_version: number | null
          updated_at: string
          validation_errors: Json
        }
        Insert: {
          company_id?: string | null
          completed_at?: string | null
          created_at?: string
          error_code?: string | null
          error_detail?: string | null
          id?: string
          idempotency_key: string
          module_results?: Json
          request_actor: string
          request_hash: string
          requested_by?: string | null
          requested_company_code?: string | null
          result?: Json | null
          started_at?: string
          status: string
          template_code: string
          template_id?: string | null
          template_version?: number | null
          updated_at?: string
          validation_errors?: Json
        }
        Update: {
          company_id?: string | null
          completed_at?: string | null
          created_at?: string
          error_code?: string | null
          error_detail?: string | null
          id?: string
          idempotency_key?: string
          module_results?: Json
          request_actor?: string
          request_hash?: string
          requested_by?: string | null
          requested_company_code?: string | null
          result?: Json | null
          started_at?: string
          status?: string
          template_code?: string
          template_id?: string | null
          template_version?: number | null
          updated_at?: string
          validation_errors?: Json
        }
        Relationships: [
          {
            foreignKeyName: "company_provisioning_runs_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_provisioning_runs_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "company_provisioning_runs_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "company_provisioning_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      company_provisioning_template_modules: {
        Row: {
          created_at: string
          execution_order: number | null
          is_enabled: boolean
          is_required: boolean
          module_code: string
          module_config: Json
          template_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          execution_order?: number | null
          is_enabled?: boolean
          is_required?: boolean
          module_code: string
          module_config?: Json
          template_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          execution_order?: number | null
          is_enabled?: boolean
          is_required?: boolean
          module_code?: string
          module_config?: Json
          template_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "company_provisioning_template_modules_module_code_fkey"
            columns: ["module_code"]
            isOneToOne: false
            referencedRelation: "company_provisioning_modules"
            referencedColumns: ["module_code"]
          },
          {
            foreignKeyName: "company_provisioning_template_modules_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "company_provisioning_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      company_provisioning_templates: {
        Row: {
          applicable_entity_types: string[]
          coa_template_code: string
          country_code: string
          created_at: string
          default_functional_currency_code: string
          default_reporting_currency_code: string
          id: string
          is_active: boolean
          is_current: boolean
          localization_code: string
          template_code: string
          template_config: Json
          template_name: string
          template_version: number
          updated_at: string
        }
        Insert: {
          applicable_entity_types?: string[]
          coa_template_code: string
          country_code: string
          created_at?: string
          default_functional_currency_code: string
          default_reporting_currency_code: string
          id?: string
          is_active?: boolean
          is_current?: boolean
          localization_code: string
          template_code: string
          template_config?: Json
          template_name: string
          template_version?: number
          updated_at?: string
        }
        Update: {
          applicable_entity_types?: string[]
          coa_template_code?: string
          country_code?: string
          created_at?: string
          default_functional_currency_code?: string
          default_reporting_currency_code?: string
          id?: string
          is_active?: boolean
          is_current?: boolean
          localization_code?: string
          template_code?: string
          template_config?: Json
          template_name?: string
          template_version?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "company_provisioning_template_default_functional_currency__fkey"
            columns: ["default_functional_currency_code"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "company_provisioning_template_default_reporting_currency_c_fkey"
            columns: ["default_reporting_currency_code"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "company_provisioning_templates_coa_template_code_fkey"
            columns: ["coa_template_code"]
            isOneToOne: false
            referencedRelation: "coa_templates"
            referencedColumns: ["template_code"]
          },
        ]
      }
      compliance_1601fq_working_papers_headers: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          description: string | null
          id: string
          period_quarter: number
          period_year: number
          status: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          period_quarter: number
          period_year: number
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          period_quarter?: number
          period_year?: number
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "compliance_1601fq_working_papers_headers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "compliance_1601fq_working_papers_headers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      compliance_1601fq_working_papers_lines: {
        Row: {
          amount: number
          created_at: string
          header_id: string
          id: string
          reference: string | null
          remarks: string | null
        }
        Insert: {
          amount?: number
          created_at?: string
          header_id: string
          id?: string
          reference?: string | null
          remarks?: string | null
        }
        Update: {
          amount?: number
          created_at?: string
          header_id?: string
          id?: string
          reference?: string | null
          remarks?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "compliance_1601fq_working_papers_lines_header_id_fkey"
            columns: ["header_id"]
            isOneToOne: false
            referencedRelation: "compliance_1601fq_working_papers_headers"
            referencedColumns: ["id"]
          },
        ]
      }
      compliance_fwt_working_papers_headers: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          description: string | null
          id: string
          period: string
          status: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          period: string
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          period?: string
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "compliance_fwt_working_papers_headers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "compliance_fwt_working_papers_headers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      compliance_fwt_working_papers_lines: {
        Row: {
          amount: number
          created_at: string
          header_id: string
          id: string
          reference: string | null
          remarks: string | null
        }
        Insert: {
          amount?: number
          created_at?: string
          header_id: string
          id?: string
          reference?: string | null
          remarks?: string | null
        }
        Update: {
          amount?: number
          created_at?: string
          header_id?: string
          id?: string
          reference?: string | null
          remarks?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "compliance_fwt_working_papers_lines_header_id_fkey"
            columns: ["header_id"]
            isOneToOne: false
            referencedRelation: "compliance_fwt_working_papers_headers"
            referencedColumns: ["id"]
          },
        ]
      }
      compliance_profiles: {
        Row: {
          company_id: string
          corporate_tax_rate: number
          created_at: string | null
          created_by: string | null
          dat_file_required: boolean | null
          efps_enrolled: boolean
          efps_group: string | null
          ewt_registered: boolean
          files_0619e: boolean
          files_0619f: boolean
          fwt_registered: boolean
          id: string
          income_tax_regime: string
          is_active: boolean | null
          is_twa: boolean
          mcit_applicable: boolean | null
          nolco_applicable: boolean | null
          percentage_tax_rate: number | null
          percentage_tax_registered: boolean
          pt_effective_date: string | null
          pt_filing_frequency: string | null
          qap_required: boolean | null
          relief_required: boolean | null
          requires_1604e: boolean | null
          sawt_required: boolean | null
          slsp_required: boolean | null
          twa_auto_ewt_enabled: boolean
          twa_effective_date: string | null
          updated_at: string | null
          updated_by: string | null
          vat_effective_date: string | null
          vat_filing_frequency: string | null
          vat_registered: boolean
          vat_threshold_monitoring: boolean | null
        }
        Insert: {
          company_id: string
          corporate_tax_rate?: number
          created_at?: string | null
          created_by?: string | null
          dat_file_required?: boolean | null
          efps_enrolled?: boolean
          efps_group?: string | null
          ewt_registered?: boolean
          files_0619e?: boolean
          files_0619f?: boolean
          fwt_registered?: boolean
          id?: string
          income_tax_regime?: string
          is_active?: boolean | null
          is_twa?: boolean
          mcit_applicable?: boolean | null
          nolco_applicable?: boolean | null
          percentage_tax_rate?: number | null
          percentage_tax_registered?: boolean
          pt_effective_date?: string | null
          pt_filing_frequency?: string | null
          qap_required?: boolean | null
          relief_required?: boolean | null
          requires_1604e?: boolean | null
          sawt_required?: boolean | null
          slsp_required?: boolean | null
          twa_auto_ewt_enabled?: boolean
          twa_effective_date?: string | null
          updated_at?: string | null
          updated_by?: string | null
          vat_effective_date?: string | null
          vat_filing_frequency?: string | null
          vat_registered?: boolean
          vat_threshold_monitoring?: boolean | null
        }
        Update: {
          company_id?: string
          corporate_tax_rate?: number
          created_at?: string | null
          created_by?: string | null
          dat_file_required?: boolean | null
          efps_enrolled?: boolean
          efps_group?: string | null
          ewt_registered?: boolean
          files_0619e?: boolean
          files_0619f?: boolean
          fwt_registered?: boolean
          id?: string
          income_tax_regime?: string
          is_active?: boolean | null
          is_twa?: boolean
          mcit_applicable?: boolean | null
          nolco_applicable?: boolean | null
          percentage_tax_rate?: number | null
          percentage_tax_registered?: boolean
          pt_effective_date?: string | null
          pt_filing_frequency?: string | null
          qap_required?: boolean | null
          relief_required?: boolean | null
          requires_1604e?: boolean | null
          sawt_required?: boolean | null
          slsp_required?: boolean | null
          twa_auto_ewt_enabled?: boolean
          twa_effective_date?: string | null
          updated_at?: string | null
          updated_by?: string | null
          vat_effective_date?: string | null
          vat_filing_frequency?: string | null
          vat_registered?: boolean
          vat_threshold_monitoring?: boolean | null
        }
        Relationships: [
          {
            foreignKeyName: "compliance_profiles_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: true
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "compliance_profiles_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: true
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      cost_centers: {
        Row: {
          branch_id: string | null
          company_id: string
          cost_center_code: string
          cost_center_name: string
          cost_center_type: string
          created_at: string | null
          created_by: string | null
          department_id: string | null
          description: string | null
          id: string
          is_active: boolean | null
          manager_user_id: string | null
          parent_cost_center_id: string | null
          updated_at: string | null
          updated_by: string | null
          valid_from: string | null
          valid_to: string | null
        }
        Insert: {
          branch_id?: string | null
          company_id: string
          cost_center_code: string
          cost_center_name: string
          cost_center_type?: string
          created_at?: string | null
          created_by?: string | null
          department_id?: string | null
          description?: string | null
          id?: string
          is_active?: boolean | null
          manager_user_id?: string | null
          parent_cost_center_id?: string | null
          updated_at?: string | null
          updated_by?: string | null
          valid_from?: string | null
          valid_to?: string | null
        }
        Update: {
          branch_id?: string | null
          company_id?: string
          cost_center_code?: string
          cost_center_name?: string
          cost_center_type?: string
          created_at?: string | null
          created_by?: string | null
          department_id?: string | null
          description?: string | null
          id?: string
          is_active?: boolean | null
          manager_user_id?: string | null
          parent_cost_center_id?: string | null
          updated_at?: string | null
          updated_by?: string | null
          valid_from?: string | null
          valid_to?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "cost_centers_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cost_centers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cost_centers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "cost_centers_department_id_fkey"
            columns: ["department_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cost_centers_parent_cost_center_id_fkey"
            columns: ["parent_cost_center_id"]
            isOneToOne: false
            referencedRelation: "cost_centers"
            referencedColumns: ["id"]
          },
        ]
      }
      credit_memo_lines: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          credit_memo_id: string
          description: string
          id: string
          inventory_cost: number | null
          inventory_cost_layer_id: string | null
          inventory_transaction_id: string | null
          invoice_line_id: string | null
          item_id: string | null
          line_number: number
          lot_number: string | null
          net_amount: number
          quantity: number
          revenue_account_id: string | null
          serial_number: string | null
          total_amount: number
          unit_cost: number | null
          unit_price: number
          updated_at: string
          updated_by: string | null
          vat_amount: number
          vat_code_id: string | null
          warehouse_id: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          credit_memo_id: string
          description: string
          id?: string
          inventory_cost?: number | null
          inventory_cost_layer_id?: string | null
          inventory_transaction_id?: string | null
          invoice_line_id?: string | null
          item_id?: string | null
          line_number?: number
          lot_number?: string | null
          net_amount?: number
          quantity?: number
          revenue_account_id?: string | null
          serial_number?: string | null
          total_amount?: number
          unit_cost?: number | null
          unit_price?: number
          updated_at?: string
          updated_by?: string | null
          vat_amount?: number
          vat_code_id?: string | null
          warehouse_id?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          credit_memo_id?: string
          description?: string
          id?: string
          inventory_cost?: number | null
          inventory_cost_layer_id?: string | null
          inventory_transaction_id?: string | null
          invoice_line_id?: string | null
          item_id?: string | null
          line_number?: number
          lot_number?: string | null
          net_amount?: number
          quantity?: number
          revenue_account_id?: string | null
          serial_number?: string | null
          total_amount?: number
          unit_cost?: number | null
          unit_price?: number
          updated_at?: string
          updated_by?: string | null
          vat_amount?: number
          vat_code_id?: string | null
          warehouse_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "credit_memo_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "credit_memo_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "credit_memo_lines_credit_memo_id_fkey"
            columns: ["credit_memo_id"]
            isOneToOne: false
            referencedRelation: "credit_memos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "credit_memo_lines_credit_memo_id_fkey"
            columns: ["credit_memo_id"]
            isOneToOne: false
            referencedRelation: "vw_credit_memo_register"
            referencedColumns: ["cm_id"]
          },
          {
            foreignKeyName: "credit_memo_lines_inventory_cost_layer_id_fkey"
            columns: ["inventory_cost_layer_id"]
            isOneToOne: false
            referencedRelation: "inventory_cost_layers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "credit_memo_lines_inventory_cost_layer_id_fkey"
            columns: ["inventory_cost_layer_id"]
            isOneToOne: false
            referencedRelation: "vw_available_inventory_identities"
            referencedColumns: ["inventory_cost_layer_id"]
          },
          {
            foreignKeyName: "credit_memo_lines_inventory_transaction_id_fkey"
            columns: ["inventory_transaction_id"]
            isOneToOne: false
            referencedRelation: "inventory_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "credit_memo_lines_invoice_line_id_fkey"
            columns: ["invoice_line_id"]
            isOneToOne: false
            referencedRelation: "sales_invoice_lines"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "credit_memo_lines_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "credit_memo_lines_revenue_account_id_fkey"
            columns: ["revenue_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "credit_memo_lines_vat_code_id_fkey"
            columns: ["vat_code_id"]
            isOneToOne: false
            referencedRelation: "vat_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "credit_memo_lines_warehouse_id_fkey"
            columns: ["warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
        ]
      }
      credit_memos: {
        Row: {
          branch_id: string
          cm_date: string
          cm_number: string
          company_id: string
          created_at: string
          created_by: string | null
          customer_id: string
          customer_name_snapshot: string
          customer_tin_snapshot: string
          id: string
          invoice_id: string | null
          journal_entry_id: string | null
          posted_at: string | null
          posted_by: string | null
          reason_code_id: string
          remarks: string | null
          status: string
          total_amount: number
          total_exempt_amount: number
          total_net_amount: number
          total_taxable_amount: number
          total_vat_amount: number
          total_zero_rated_amount: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          branch_id: string
          cm_date?: string
          cm_number: string
          company_id: string
          created_at?: string
          created_by?: string | null
          customer_id: string
          customer_name_snapshot?: string
          customer_tin_snapshot?: string
          id?: string
          invoice_id?: string | null
          journal_entry_id?: string | null
          posted_at?: string | null
          posted_by?: string | null
          reason_code_id: string
          remarks?: string | null
          status?: string
          total_amount?: number
          total_exempt_amount?: number
          total_net_amount?: number
          total_taxable_amount?: number
          total_vat_amount?: number
          total_zero_rated_amount?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          branch_id?: string
          cm_date?: string
          cm_number?: string
          company_id?: string
          created_at?: string
          created_by?: string | null
          customer_id?: string
          customer_name_snapshot?: string
          customer_tin_snapshot?: string
          id?: string
          invoice_id?: string | null
          journal_entry_id?: string | null
          posted_at?: string | null
          posted_by?: string | null
          reason_code_id?: string
          remarks?: string | null
          status?: string
          total_amount?: number
          total_exempt_amount?: number
          total_net_amount?: number
          total_taxable_amount?: number
          total_vat_amount?: number
          total_zero_rated_amount?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "credit_memos_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "credit_memos_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "credit_memos_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "credit_memos_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "credit_memos_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "sales_invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "credit_memos_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "vw_sales_invoice_register"
            referencedColumns: ["invoice_id"]
          },
          {
            foreignKeyName: "credit_memos_reason_code_id_fkey"
            columns: ["reason_code_id"]
            isOneToOne: false
            referencedRelation: "ref_reason_codes"
            referencedColumns: ["id"]
          },
        ]
      }
      currencies: {
        Row: {
          created_at: string | null
          currency_code: string
          decimal_places: number
          id: string
          is_active: boolean | null
          is_base: boolean | null
          name: string
          symbol: string
        }
        Insert: {
          created_at?: string | null
          currency_code: string
          decimal_places?: number
          id?: string
          is_active?: boolean | null
          is_base?: boolean | null
          name: string
          symbol: string
        }
        Update: {
          created_at?: string | null
          currency_code?: string
          decimal_places?: number
          id?: string
          is_active?: boolean | null
          is_base?: boolean | null
          name?: string
          symbol?: string
        }
        Relationships: []
      }
      customer_groups: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          description: string | null
          group_code: string
          group_name: string
          id: string
          is_active: boolean
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          group_code: string
          group_name: string
          id?: string
          is_active?: boolean
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          group_code?: string
          group_name?: string
          id?: string
          is_active?: boolean
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "customer_groups_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_groups_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      customers: {
        Row: {
          business_style: string | null
          company_id: string
          contact_person: string | null
          created_at: string | null
          created_by: string | null
          credit_limit: number | null
          customer_code: string
          customer_group: string | null
          customer_group_id: string | null
          default_currency_id: string | null
          default_cwt_atc_code_id: string | null
          default_gl_account_id: string | null
          default_tax_type: string
          default_terms_id: string | null
          delivery_address: string
          email: string | null
          id: string
          is_active: boolean | null
          is_subject_to_cwt: boolean
          phone_number: string | null
          registered_address: string
          registered_name: string
          tin: string
          tin_branch_code: string
          trade_name: string | null
          updated_at: string | null
          updated_by: string | null
        }
        Insert: {
          business_style?: string | null
          company_id: string
          contact_person?: string | null
          created_at?: string | null
          created_by?: string | null
          credit_limit?: number | null
          customer_code: string
          customer_group?: string | null
          customer_group_id?: string | null
          default_currency_id?: string | null
          default_cwt_atc_code_id?: string | null
          default_gl_account_id?: string | null
          default_tax_type?: string
          default_terms_id?: string | null
          delivery_address: string
          email?: string | null
          id?: string
          is_active?: boolean | null
          is_subject_to_cwt?: boolean
          phone_number?: string | null
          registered_address: string
          registered_name: string
          tin: string
          tin_branch_code?: string
          trade_name?: string | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Update: {
          business_style?: string | null
          company_id?: string
          contact_person?: string | null
          created_at?: string | null
          created_by?: string | null
          credit_limit?: number | null
          customer_code?: string
          customer_group?: string | null
          customer_group_id?: string | null
          default_currency_id?: string | null
          default_cwt_atc_code_id?: string | null
          default_gl_account_id?: string | null
          default_tax_type?: string
          default_terms_id?: string | null
          delivery_address?: string
          email?: string | null
          id?: string
          is_active?: boolean | null
          is_subject_to_cwt?: boolean
          phone_number?: string | null
          registered_address?: string
          registered_name?: string
          tin?: string
          tin_branch_code?: string
          trade_name?: string | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "customers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "customers_customer_group_id_fkey"
            columns: ["customer_group_id"]
            isOneToOne: false
            referencedRelation: "customer_groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customers_default_currency_id_fkey"
            columns: ["default_currency_id"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customers_default_cwt_atc_code_id_fkey"
            columns: ["default_cwt_atc_code_id"]
            isOneToOne: false
            referencedRelation: "atc_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customers_default_gl_account_id_fkey"
            columns: ["default_gl_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customers_default_terms_id_fkey"
            columns: ["default_terms_id"]
            isOneToOne: false
            referencedRelation: "payment_terms"
            referencedColumns: ["id"]
          },
        ]
      }
      dashboard_layouts: {
        Row: {
          created_at: string
          created_by: string | null
          default_date_filter: string
          description: string | null
          id: string
          is_default_view: boolean
          layout_name: string
          target_role: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          default_date_filter?: string
          description?: string | null
          id?: string
          is_default_view?: boolean
          layout_name: string
          target_role: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          default_date_filter?: string
          description?: string | null
          id?: string
          is_default_view?: boolean
          layout_name?: string
          target_role?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      dashboard_widgets: {
        Row: {
          created_at: string
          created_by: string | null
          custom_filter_json: Json | null
          dashboard_layout_id: string
          grid_height: number
          grid_pos_x: number
          grid_pos_y: number
          grid_width: number
          id: string
          kpi_source: string
          updated_at: string
          updated_by: string | null
          widget_type: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          custom_filter_json?: Json | null
          dashboard_layout_id: string
          grid_height?: number
          grid_pos_x?: number
          grid_pos_y?: number
          grid_width?: number
          id?: string
          kpi_source: string
          updated_at?: string
          updated_by?: string | null
          widget_type: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          custom_filter_json?: Json | null
          dashboard_layout_id?: string
          grid_height?: number
          grid_pos_x?: number
          grid_pos_y?: number
          grid_width?: number
          id?: string
          kpi_source?: string
          updated_at?: string
          updated_by?: string | null
          widget_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "dashboard_widgets_dashboard_layout_id_fkey"
            columns: ["dashboard_layout_id"]
            isOneToOne: false
            referencedRelation: "dashboard_layouts"
            referencedColumns: ["id"]
          },
        ]
      }
      debit_memo_lines: {
        Row: {
          account_id: string | null
          amount: number
          company_id: string
          created_at: string
          created_by: string | null
          debit_memo_id: string
          description: string
          id: string
          item_id: string | null
          line_number: number
          total_amount: number
          updated_at: string
          updated_by: string | null
          vat_amount: number
          vat_code_id: string | null
        }
        Insert: {
          account_id?: string | null
          amount?: number
          company_id: string
          created_at?: string
          created_by?: string | null
          debit_memo_id: string
          description: string
          id?: string
          item_id?: string | null
          line_number?: number
          total_amount?: number
          updated_at?: string
          updated_by?: string | null
          vat_amount?: number
          vat_code_id?: string | null
        }
        Update: {
          account_id?: string | null
          amount?: number
          company_id?: string
          created_at?: string
          created_by?: string | null
          debit_memo_id?: string
          description?: string
          id?: string
          item_id?: string | null
          line_number?: number
          total_amount?: number
          updated_at?: string
          updated_by?: string | null
          vat_amount?: number
          vat_code_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "debit_memo_lines_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "debit_memo_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "debit_memo_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "debit_memo_lines_debit_memo_id_fkey"
            columns: ["debit_memo_id"]
            isOneToOne: false
            referencedRelation: "debit_memos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "debit_memo_lines_debit_memo_id_fkey"
            columns: ["debit_memo_id"]
            isOneToOne: false
            referencedRelation: "vw_debit_memo_register"
            referencedColumns: ["dm_id"]
          },
          {
            foreignKeyName: "debit_memo_lines_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "debit_memo_lines_vat_code_id_fkey"
            columns: ["vat_code_id"]
            isOneToOne: false
            referencedRelation: "vat_codes"
            referencedColumns: ["id"]
          },
        ]
      }
      debit_memos: {
        Row: {
          branch_id: string
          company_id: string
          created_at: string
          created_by: string | null
          customer_id: string
          customer_name_snapshot: string
          customer_tin_snapshot: string
          dm_date: string
          dm_number: string
          id: string
          journal_entry_id: string | null
          posted_at: string | null
          posted_by: string | null
          reason_code_id: string
          remarks: string | null
          source_doc_id: string | null
          source_doc_type: string | null
          status: string
          total_amount: number
          total_exempt_amount: number
          total_net_amount: number
          total_taxable_amount: number
          total_vat_amount: number
          total_zero_rated_amount: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          branch_id: string
          company_id: string
          created_at?: string
          created_by?: string | null
          customer_id: string
          customer_name_snapshot?: string
          customer_tin_snapshot?: string
          dm_date?: string
          dm_number: string
          id?: string
          journal_entry_id?: string | null
          posted_at?: string | null
          posted_by?: string | null
          reason_code_id: string
          remarks?: string | null
          source_doc_id?: string | null
          source_doc_type?: string | null
          status?: string
          total_amount?: number
          total_exempt_amount?: number
          total_net_amount?: number
          total_taxable_amount?: number
          total_vat_amount?: number
          total_zero_rated_amount?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          branch_id?: string
          company_id?: string
          created_at?: string
          created_by?: string | null
          customer_id?: string
          customer_name_snapshot?: string
          customer_tin_snapshot?: string
          dm_date?: string
          dm_number?: string
          id?: string
          journal_entry_id?: string | null
          posted_at?: string | null
          posted_by?: string | null
          reason_code_id?: string
          remarks?: string | null
          source_doc_id?: string | null
          source_doc_type?: string | null
          status?: string
          total_amount?: number
          total_exempt_amount?: number
          total_net_amount?: number
          total_taxable_amount?: number
          total_vat_amount?: number
          total_zero_rated_amount?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "debit_memos_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "debit_memos_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "debit_memos_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "debit_memos_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "debit_memos_reason_code_id_fkey"
            columns: ["reason_code_id"]
            isOneToOne: false
            referencedRelation: "ref_reason_codes"
            referencedColumns: ["id"]
          },
        ]
      }
      delivery_receipt_lines: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          description: string
          dr_id: string
          id: string
          inventory_cost: number | null
          inventory_cost_layer_id: string | null
          inventory_transaction_id: string | null
          item_id: string | null
          line_number: number
          lot_number: string | null
          lot_serial_no: string | null
          quantity: number
          serial_number: string | null
          so_line_id: string | null
          unit_cost: number | null
          uom_id: string | null
          updated_at: string
          updated_by: string | null
          warehouse_id: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          description: string
          dr_id: string
          id?: string
          inventory_cost?: number | null
          inventory_cost_layer_id?: string | null
          inventory_transaction_id?: string | null
          item_id?: string | null
          line_number?: number
          lot_number?: string | null
          lot_serial_no?: string | null
          quantity?: number
          serial_number?: string | null
          so_line_id?: string | null
          unit_cost?: number | null
          uom_id?: string | null
          updated_at?: string
          updated_by?: string | null
          warehouse_id?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          description?: string
          dr_id?: string
          id?: string
          inventory_cost?: number | null
          inventory_cost_layer_id?: string | null
          inventory_transaction_id?: string | null
          item_id?: string | null
          line_number?: number
          lot_number?: string | null
          lot_serial_no?: string | null
          quantity?: number
          serial_number?: string | null
          so_line_id?: string | null
          unit_cost?: number | null
          uom_id?: string | null
          updated_at?: string
          updated_by?: string | null
          warehouse_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "delivery_receipt_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "delivery_receipt_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "delivery_receipt_lines_dr_id_fkey"
            columns: ["dr_id"]
            isOneToOne: false
            referencedRelation: "delivery_receipts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "delivery_receipt_lines_inventory_cost_layer_id_fkey"
            columns: ["inventory_cost_layer_id"]
            isOneToOne: false
            referencedRelation: "inventory_cost_layers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "delivery_receipt_lines_inventory_cost_layer_id_fkey"
            columns: ["inventory_cost_layer_id"]
            isOneToOne: false
            referencedRelation: "vw_available_inventory_identities"
            referencedColumns: ["inventory_cost_layer_id"]
          },
          {
            foreignKeyName: "delivery_receipt_lines_inventory_transaction_id_fkey"
            columns: ["inventory_transaction_id"]
            isOneToOne: false
            referencedRelation: "inventory_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "delivery_receipt_lines_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "delivery_receipt_lines_so_line_id_fkey"
            columns: ["so_line_id"]
            isOneToOne: false
            referencedRelation: "sales_order_lines"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "delivery_receipt_lines_uom_id_fkey"
            columns: ["uom_id"]
            isOneToOne: false
            referencedRelation: "units_of_measure"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "delivery_receipt_lines_warehouse_id_fkey"
            columns: ["warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
        ]
      }
      delivery_receipts: {
        Row: {
          branch_id: string
          company_id: string
          created_at: string
          created_by: string | null
          customer_id: string
          customer_name_snapshot: string
          delivered_at: string | null
          delivery_address: string
          dr_date: string
          dr_number: string
          driver_name: string | null
          id: string
          journal_entry_id: string | null
          posted_at: string | null
          posted_by: string | null
          sales_order_id: string | null
          shipping_method: string
          status: string
          tracking_number: string | null
          updated_at: string
          updated_by: string | null
          void_memo: string | null
          void_reason_id: string | null
        }
        Insert: {
          branch_id: string
          company_id: string
          created_at?: string
          created_by?: string | null
          customer_id: string
          customer_name_snapshot?: string
          delivered_at?: string | null
          delivery_address?: string
          dr_date?: string
          dr_number: string
          driver_name?: string | null
          id?: string
          journal_entry_id?: string | null
          posted_at?: string | null
          posted_by?: string | null
          sales_order_id?: string | null
          shipping_method?: string
          status?: string
          tracking_number?: string | null
          updated_at?: string
          updated_by?: string | null
          void_memo?: string | null
          void_reason_id?: string | null
        }
        Update: {
          branch_id?: string
          company_id?: string
          created_at?: string
          created_by?: string | null
          customer_id?: string
          customer_name_snapshot?: string
          delivered_at?: string | null
          delivery_address?: string
          dr_date?: string
          dr_number?: string
          driver_name?: string | null
          id?: string
          journal_entry_id?: string | null
          posted_at?: string | null
          posted_by?: string | null
          sales_order_id?: string | null
          shipping_method?: string
          status?: string
          tracking_number?: string | null
          updated_at?: string
          updated_by?: string | null
          void_memo?: string | null
          void_reason_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "delivery_receipts_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "delivery_receipts_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "delivery_receipts_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "delivery_receipts_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "delivery_receipts_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "delivery_receipts_sales_order_id_fkey"
            columns: ["sales_order_id"]
            isOneToOne: false
            referencedRelation: "sales_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "delivery_receipts_void_reason_id_fkey"
            columns: ["void_reason_id"]
            isOneToOne: false
            referencedRelation: "void_reason_codes"
            referencedColumns: ["id"]
          },
        ]
      }
      departments: {
        Row: {
          branch_id: string | null
          company_id: string
          created_at: string | null
          created_by: string | null
          department_code: string
          department_head_name: string | null
          department_head_user_id: string | null
          department_name: string
          description: string | null
          id: string
          is_active: boolean | null
          parent_department_id: string | null
          updated_at: string | null
          updated_by: string | null
        }
        Insert: {
          branch_id?: string | null
          company_id: string
          created_at?: string | null
          created_by?: string | null
          department_code: string
          department_head_name?: string | null
          department_head_user_id?: string | null
          department_name: string
          description?: string | null
          id?: string
          is_active?: boolean | null
          parent_department_id?: string | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Update: {
          branch_id?: string | null
          company_id?: string
          created_at?: string | null
          created_by?: string | null
          department_code?: string
          department_head_name?: string | null
          department_head_user_id?: string | null
          department_name?: string
          description?: string | null
          id?: string
          is_active?: boolean | null
          parent_department_id?: string | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "departments_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "departments_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "departments_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "departments_parent_department_id_fkey"
            columns: ["parent_department_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
        ]
      }
      employees: {
        Row: {
          address_line: string | null
          birth_date: string | null
          branch_id: string | null
          city_municipality: string | null
          civil_status: string | null
          company_id: string
          created_at: string
          created_by: string | null
          department_id: string | null
          email: string | null
          employee_number: string
          employment_type: string
          first_name: string
          gender: string | null
          hire_date: string
          id: string
          is_active: boolean
          is_buyer: boolean
          is_salesperson: boolean
          job_title: string | null
          last_name: string
          middle_name: string | null
          mobile: string | null
          notes: string | null
          pagibig_no: string | null
          philhealth_no: string | null
          province: string | null
          regularization_date: string | null
          separation_date: string | null
          separation_reason: string | null
          sss_no: string | null
          suffix: string | null
          tin: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          address_line?: string | null
          birth_date?: string | null
          branch_id?: string | null
          city_municipality?: string | null
          civil_status?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          department_id?: string | null
          email?: string | null
          employee_number: string
          employment_type?: string
          first_name: string
          gender?: string | null
          hire_date: string
          id?: string
          is_active?: boolean
          is_buyer?: boolean
          is_salesperson?: boolean
          job_title?: string | null
          last_name: string
          middle_name?: string | null
          mobile?: string | null
          notes?: string | null
          pagibig_no?: string | null
          philhealth_no?: string | null
          province?: string | null
          regularization_date?: string | null
          separation_date?: string | null
          separation_reason?: string | null
          sss_no?: string | null
          suffix?: string | null
          tin?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          address_line?: string | null
          birth_date?: string | null
          branch_id?: string | null
          city_municipality?: string | null
          civil_status?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          department_id?: string | null
          email?: string | null
          employee_number?: string
          employment_type?: string
          first_name?: string
          gender?: string | null
          hire_date?: string
          id?: string
          is_active?: boolean
          is_buyer?: boolean
          is_salesperson?: boolean
          job_title?: string | null
          last_name?: string
          middle_name?: string | null
          mobile?: string | null
          notes?: string | null
          pagibig_no?: string | null
          philhealth_no?: string | null
          province?: string | null
          regularization_date?: string | null
          separation_date?: string | null
          separation_reason?: string | null
          sss_no?: string | null
          suffix?: string | null
          tin?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "employees_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employees_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employees_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "employees_department_id_fkey"
            columns: ["department_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
        ]
      }
      ewt_returns: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          filed_date: string | null
          id: string
          period_quarter: number
          period_year: number
          reference_no: string | null
          remarks: string | null
          remitted_prior: number
          status: string
          still_due: number
          total_ewt_withheld: number
          total_tax_base: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          filed_date?: string | null
          id?: string
          period_quarter: number
          period_year: number
          reference_no?: string | null
          remarks?: string | null
          remitted_prior?: number
          status?: string
          still_due?: number
          total_ewt_withheld?: number
          total_tax_base?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          filed_date?: string | null
          id?: string
          period_quarter?: number
          period_year?: number
          reference_no?: string | null
          remarks?: string | null
          remitted_prior?: number
          status?: string
          still_due?: number
          total_ewt_withheld?: number
          total_tax_base?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ewt_returns_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ewt_returns_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      exchange_rates: {
        Row: {
          company_id: string
          created_at: string | null
          created_by: string | null
          currency_id: string
          id: string
          rate: number
          rate_date: string
          rate_type: string
          source: string
        }
        Insert: {
          company_id: string
          created_at?: string | null
          created_by?: string | null
          currency_id: string
          id?: string
          rate: number
          rate_date: string
          rate_type?: string
          source?: string
        }
        Update: {
          company_id?: string
          created_at?: string | null
          created_by?: string | null
          currency_id?: string
          id?: string
          rate?: number
          rate_date?: string
          rate_type?: string
          source?: string
        }
        Relationships: [
          {
            foreignKeyName: "exchange_rates_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "exchange_rates_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "exchange_rates_currency_id_fkey"
            columns: ["currency_id"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["id"]
          },
        ]
      }
      filing_artifact_lines: {
        Row: {
          artifact_id: string
          atc_code: string | null
          classification: string | null
          counterparty_id: string | null
          counterparty_name: string | null
          counterparty_tin: string | null
          created_at: string
          created_by: string | null
          document_count: number
          id: string
          line_kind: string
          line_number: number
          reason: string | null
          reconciling_amount: number | null
          reference: string | null
          remarks: string | null
          tax_amount: number
          tax_base: number
          tax_code: string | null
          tax_kind: string | null
          tax_rate: number | null
          updated_at: string
          updated_by: string | null
          vat_code: string | null
        }
        Insert: {
          artifact_id: string
          atc_code?: string | null
          classification?: string | null
          counterparty_id?: string | null
          counterparty_name?: string | null
          counterparty_tin?: string | null
          created_at?: string
          created_by?: string | null
          document_count?: number
          id?: string
          line_kind?: string
          line_number: number
          reason?: string | null
          reconciling_amount?: number | null
          reference?: string | null
          remarks?: string | null
          tax_amount?: number
          tax_base?: number
          tax_code?: string | null
          tax_kind?: string | null
          tax_rate?: number | null
          updated_at?: string
          updated_by?: string | null
          vat_code?: string | null
        }
        Update: {
          artifact_id?: string
          atc_code?: string | null
          classification?: string | null
          counterparty_id?: string | null
          counterparty_name?: string | null
          counterparty_tin?: string | null
          created_at?: string
          created_by?: string | null
          document_count?: number
          id?: string
          line_kind?: string
          line_number?: number
          reason?: string | null
          reconciling_amount?: number | null
          reference?: string | null
          remarks?: string | null
          tax_amount?: number
          tax_base?: number
          tax_code?: string | null
          tax_kind?: string | null
          tax_rate?: number | null
          updated_at?: string
          updated_by?: string | null
          vat_code?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "filing_artifact_lines_artifact_id_fkey"
            columns: ["artifact_id"]
            isOneToOne: false
            referencedRelation: "filing_artifacts"
            referencedColumns: ["id"]
          },
        ]
      }
      filing_artifacts: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          filed_date: string | null
          form_code: string
          generated_at: string
          id: string
          net_tax_payable: number | null
          period_from: string
          period_number: number
          period_to: string
          period_year: number
          reference_no: string | null
          remarks: string | null
          status: string
          summary: Json
          total_tax_amount: number
          total_tax_base: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          filed_date?: string | null
          form_code: string
          generated_at?: string
          id?: string
          net_tax_payable?: number | null
          period_from: string
          period_number: number
          period_to: string
          period_year: number
          reference_no?: string | null
          remarks?: string | null
          status?: string
          summary?: Json
          total_tax_amount?: number
          total_tax_base?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          filed_date?: string | null
          form_code?: string
          generated_at?: string
          id?: string
          net_tax_payable?: number | null
          period_from?: string
          period_number?: number
          period_to?: string
          period_year?: number
          reference_no?: string | null
          remarks?: string | null
          status?: string
          summary?: Json
          total_tax_amount?: number
          total_tax_base?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "filing_artifacts_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "filing_artifacts_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "filing_artifacts_form_code_fkey"
            columns: ["form_code"]
            isOneToOne: false
            referencedRelation: "ref_filing_artifact"
            referencedColumns: ["form_code"]
          },
        ]
      }
      fiscal_close_runs: {
        Row: {
          action: string
          checks: Json
          close_type: string
          closing_je_id: string | null
          company_id: string
          effective_date: string
          fiscal_period_id: string | null
          fiscal_year_id: string
          id: string
          net_income: number | null
          performed_at: string
          performed_by: string | null
          quarter_number: number | null
          reason: string | null
          retained_earnings_account_id: string | null
          superseded_by_id: string | null
        }
        Insert: {
          action: string
          checks?: Json
          close_type: string
          closing_je_id?: string | null
          company_id: string
          effective_date: string
          fiscal_period_id?: string | null
          fiscal_year_id: string
          id?: string
          net_income?: number | null
          performed_at?: string
          performed_by?: string | null
          quarter_number?: number | null
          reason?: string | null
          retained_earnings_account_id?: string | null
          superseded_by_id?: string | null
        }
        Update: {
          action?: string
          checks?: Json
          close_type?: string
          closing_je_id?: string | null
          company_id?: string
          effective_date?: string
          fiscal_period_id?: string | null
          fiscal_year_id?: string
          id?: string
          net_income?: number | null
          performed_at?: string
          performed_by?: string | null
          quarter_number?: number | null
          reason?: string | null
          retained_earnings_account_id?: string | null
          superseded_by_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fiscal_close_runs_closing_je_id_fkey"
            columns: ["closing_je_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fiscal_close_runs_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fiscal_close_runs_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "fiscal_close_runs_fiscal_period_id_fkey"
            columns: ["fiscal_period_id"]
            isOneToOne: false
            referencedRelation: "fiscal_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fiscal_close_runs_fiscal_year_id_fkey"
            columns: ["fiscal_year_id"]
            isOneToOne: false
            referencedRelation: "fiscal_years"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fiscal_close_runs_retained_earnings_account_id_fkey"
            columns: ["retained_earnings_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fiscal_close_runs_superseded_by_id_fkey"
            columns: ["superseded_by_id"]
            isOneToOne: false
            referencedRelation: "fiscal_close_runs"
            referencedColumns: ["id"]
          },
        ]
      }
      fiscal_periods: {
        Row: {
          company_id: string
          created_at: string | null
          end_date: string
          fiscal_year_id: string
          id: string
          is_locked: boolean | null
          period_name: string
          period_number: number
          start_date: string
          updated_at: string | null
        }
        Insert: {
          company_id: string
          created_at?: string | null
          end_date: string
          fiscal_year_id: string
          id?: string
          is_locked?: boolean | null
          period_name: string
          period_number: number
          start_date: string
          updated_at?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string | null
          end_date?: string
          fiscal_year_id?: string
          id?: string
          is_locked?: boolean | null
          period_name?: string
          period_number?: number
          start_date?: string
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fiscal_periods_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fiscal_periods_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "fiscal_periods_fiscal_year_id_fkey"
            columns: ["fiscal_year_id"]
            isOneToOne: false
            referencedRelation: "fiscal_years"
            referencedColumns: ["id"]
          },
        ]
      }
      fiscal_years: {
        Row: {
          company_id: string
          created_at: string | null
          created_by: string | null
          end_date: string
          id: string
          is_calendar: boolean | null
          retained_earnings_id: string | null
          start_date: string
          status: string
          updated_at: string | null
          updated_by: string | null
          year_name: string
        }
        Insert: {
          company_id: string
          created_at?: string | null
          created_by?: string | null
          end_date: string
          id?: string
          is_calendar?: boolean | null
          retained_earnings_id?: string | null
          start_date: string
          status?: string
          updated_at?: string | null
          updated_by?: string | null
          year_name: string
        }
        Update: {
          company_id?: string
          created_at?: string | null
          created_by?: string | null
          end_date?: string
          id?: string
          is_calendar?: boolean | null
          retained_earnings_id?: string | null
          start_date?: string
          status?: string
          updated_at?: string | null
          updated_by?: string | null
          year_name?: string
        }
        Relationships: [
          {
            foreignKeyName: "fiscal_years_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fiscal_years_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "fiscal_years_retained_earnings_fk"
            columns: ["retained_earnings_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      fixed_asset_categories: {
        Row: {
          category_code: string
          category_name: string
          company_id: string
          created_at: string
          created_by: string | null
          depreciation_method: string
          gl_accum_depr_account_id: string | null
          gl_asset_account_id: string | null
          gl_depr_expense_account_id: string | null
          gl_gain_on_disposal_account_id: string | null
          gl_impairment_loss_account_id: string | null
          gl_loss_on_disposal_account_id: string | null
          id: string
          is_active: boolean
          salvage_rate: number
          updated_at: string
          updated_by: string | null
          useful_life_months: number
        }
        Insert: {
          category_code: string
          category_name: string
          company_id: string
          created_at?: string
          created_by?: string | null
          depreciation_method?: string
          gl_accum_depr_account_id?: string | null
          gl_asset_account_id?: string | null
          gl_depr_expense_account_id?: string | null
          gl_gain_on_disposal_account_id?: string | null
          gl_impairment_loss_account_id?: string | null
          gl_loss_on_disposal_account_id?: string | null
          id?: string
          is_active?: boolean
          salvage_rate?: number
          updated_at?: string
          updated_by?: string | null
          useful_life_months?: number
        }
        Update: {
          category_code?: string
          category_name?: string
          company_id?: string
          created_at?: string
          created_by?: string | null
          depreciation_method?: string
          gl_accum_depr_account_id?: string | null
          gl_asset_account_id?: string | null
          gl_depr_expense_account_id?: string | null
          gl_gain_on_disposal_account_id?: string | null
          gl_impairment_loss_account_id?: string | null
          gl_loss_on_disposal_account_id?: string | null
          id?: string
          is_active?: boolean
          salvage_rate?: number
          updated_at?: string
          updated_by?: string | null
          useful_life_months?: number
        }
        Relationships: [
          {
            foreignKeyName: "fixed_asset_categories_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fixed_asset_categories_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "fixed_asset_categories_gl_accum_depr_account_id_fkey"
            columns: ["gl_accum_depr_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fixed_asset_categories_gl_asset_account_id_fkey"
            columns: ["gl_asset_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fixed_asset_categories_gl_depr_expense_account_id_fkey"
            columns: ["gl_depr_expense_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fixed_asset_categories_gl_gain_on_disposal_account_id_fkey"
            columns: ["gl_gain_on_disposal_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fixed_asset_categories_gl_impairment_loss_account_id_fkey"
            columns: ["gl_impairment_loss_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fixed_asset_categories_gl_loss_on_disposal_account_id_fkey"
            columns: ["gl_loss_on_disposal_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      fixed_assets: {
        Row: {
          acquisition_cost: number
          acquisition_date: string
          acquisition_je_id: string | null
          asset_name: string
          asset_number: string
          branch_id: string | null
          category_id: string
          company_id: string
          cost_center_id: string | null
          created_at: string
          created_by: string | null
          department_id: string | null
          depreciation_method: string
          depreciation_start_date: string
          description: string | null
          disposed_at: string | null
          fiscal_period_id: string | null
          functional_entity_id: string | null
          id: string
          location: string | null
          location_id: string | null
          notes: string | null
          project_id: string | null
          salvage_value: number
          serial_number: string | null
          status: string
          supplier_id: string | null
          updated_at: string
          updated_by: string | null
          useful_life_months: number
        }
        Insert: {
          acquisition_cost: number
          acquisition_date: string
          acquisition_je_id?: string | null
          asset_name: string
          asset_number: string
          branch_id?: string | null
          category_id: string
          company_id: string
          cost_center_id?: string | null
          created_at?: string
          created_by?: string | null
          department_id?: string | null
          depreciation_method: string
          depreciation_start_date: string
          description?: string | null
          disposed_at?: string | null
          fiscal_period_id?: string | null
          functional_entity_id?: string | null
          id?: string
          location?: string | null
          location_id?: string | null
          notes?: string | null
          project_id?: string | null
          salvage_value?: number
          serial_number?: string | null
          status?: string
          supplier_id?: string | null
          updated_at?: string
          updated_by?: string | null
          useful_life_months: number
        }
        Update: {
          acquisition_cost?: number
          acquisition_date?: string
          acquisition_je_id?: string | null
          asset_name?: string
          asset_number?: string
          branch_id?: string | null
          category_id?: string
          company_id?: string
          cost_center_id?: string | null
          created_at?: string
          created_by?: string | null
          department_id?: string | null
          depreciation_method?: string
          depreciation_start_date?: string
          description?: string | null
          disposed_at?: string | null
          fiscal_period_id?: string | null
          functional_entity_id?: string | null
          id?: string
          location?: string | null
          location_id?: string | null
          notes?: string | null
          project_id?: string | null
          salvage_value?: number
          serial_number?: string | null
          status?: string
          supplier_id?: string | null
          updated_at?: string
          updated_by?: string | null
          useful_life_months?: number
        }
        Relationships: [
          {
            foreignKeyName: "fixed_assets_acquisition_je_id_fkey"
            columns: ["acquisition_je_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fixed_assets_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fixed_assets_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "fixed_asset_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fixed_assets_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fixed_assets_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "fixed_assets_cost_center_id_fkey"
            columns: ["cost_center_id"]
            isOneToOne: false
            referencedRelation: "cost_centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fixed_assets_department_id_fkey"
            columns: ["department_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fixed_assets_fiscal_period_id_fkey"
            columns: ["fiscal_period_id"]
            isOneToOne: false
            referencedRelation: "fiscal_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fixed_assets_functional_entity_id_fkey"
            columns: ["functional_entity_id"]
            isOneToOne: false
            referencedRelation: "functional_entities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fixed_assets_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fixed_assets_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fixed_assets_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
      form_2306_issuances: {
        Row: {
          bank_account_id: string
          certificate_number: string | null
          company_id: string
          created_at: string
          created_by: string | null
          date_acknowledged: string | null
          date_generated: string | null
          date_sent: string | null
          fwt_rate: number
          fwt_withheld: number
          gross_interest_income: number
          id: string
          period_quarter: number
          period_year: number
          remarks: string | null
          status: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          bank_account_id: string
          certificate_number?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          date_acknowledged?: string | null
          date_generated?: string | null
          date_sent?: string | null
          fwt_rate?: number
          fwt_withheld?: number
          gross_interest_income?: number
          id?: string
          period_quarter: number
          period_year: number
          remarks?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          bank_account_id?: string
          certificate_number?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          date_acknowledged?: string | null
          date_generated?: string | null
          date_sent?: string | null
          fwt_rate?: number
          fwt_withheld?: number
          gross_interest_income?: number
          id?: string
          period_quarter?: number
          period_year?: number
          remarks?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "form_2306_issuances_bank_account_id_fkey"
            columns: ["bank_account_id"]
            isOneToOne: false
            referencedRelation: "bank_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "form_2306_issuances_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "form_2306_issuances_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      form_2307_issuance_lines: {
        Row: {
          atc_code: string
          atc_code_id: string | null
          company_id: string
          created_at: string
          id: string
          issuance_id: string
          month_1_tax_base: number
          month_1_tax_withheld: number
          month_2_tax_base: number
          month_2_tax_withheld: number
          month_3_tax_base: number
          month_3_tax_withheld: number
          nature_of_income: string
          tax_base: number
          tax_rate: number | null
          tax_withheld: number
        }
        Insert: {
          atc_code: string
          atc_code_id?: string | null
          company_id: string
          created_at?: string
          id?: string
          issuance_id: string
          month_1_tax_base?: number
          month_1_tax_withheld?: number
          month_2_tax_base?: number
          month_2_tax_withheld?: number
          month_3_tax_base?: number
          month_3_tax_withheld?: number
          nature_of_income?: string
          tax_base?: number
          tax_rate?: number | null
          tax_withheld?: number
        }
        Update: {
          atc_code?: string
          atc_code_id?: string | null
          company_id?: string
          created_at?: string
          id?: string
          issuance_id?: string
          month_1_tax_base?: number
          month_1_tax_withheld?: number
          month_2_tax_base?: number
          month_2_tax_withheld?: number
          month_3_tax_base?: number
          month_3_tax_withheld?: number
          nature_of_income?: string
          tax_base?: number
          tax_rate?: number | null
          tax_withheld?: number
        }
        Relationships: [
          {
            foreignKeyName: "form_2307_issuance_lines_atc_code_id_fkey"
            columns: ["atc_code_id"]
            isOneToOne: false
            referencedRelation: "atc_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "form_2307_issuance_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "form_2307_issuance_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "form_2307_issuance_lines_issuance_id_fkey"
            columns: ["issuance_id"]
            isOneToOne: false
            referencedRelation: "form_2307_issuances"
            referencedColumns: ["id"]
          },
        ]
      }
      form_2307_issuances: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          date_acknowledged: string | null
          date_generated: string | null
          date_sent: string | null
          id: string
          remarks: string | null
          requires_supersede: boolean
          status: string
          supersede_reason: string | null
          supersede_required_at: string | null
          superseded_at: string | null
          superseded_by_issuance_id: string | null
          supersedes_issuance_id: string | null
          supplier_id: string
          tax_quarter: number
          tax_year: number
          total_ewt: number
          total_tax_base: number
          updated_at: string
          updated_by: string | null
          version: number
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          date_acknowledged?: string | null
          date_generated?: string | null
          date_sent?: string | null
          id?: string
          remarks?: string | null
          requires_supersede?: boolean
          status?: string
          supersede_reason?: string | null
          supersede_required_at?: string | null
          superseded_at?: string | null
          superseded_by_issuance_id?: string | null
          supersedes_issuance_id?: string | null
          supplier_id: string
          tax_quarter: number
          tax_year: number
          total_ewt?: number
          total_tax_base?: number
          updated_at?: string
          updated_by?: string | null
          version?: number
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          date_acknowledged?: string | null
          date_generated?: string | null
          date_sent?: string | null
          id?: string
          remarks?: string | null
          requires_supersede?: boolean
          status?: string
          supersede_reason?: string | null
          supersede_required_at?: string | null
          superseded_at?: string | null
          superseded_by_issuance_id?: string | null
          supersedes_issuance_id?: string | null
          supplier_id?: string
          tax_quarter?: number
          tax_year?: number
          total_ewt?: number
          total_tax_base?: number
          updated_at?: string
          updated_by?: string | null
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "form_2307_issuances_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "form_2307_issuances_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "form_2307_issuances_superseded_by_issuance_id_fkey"
            columns: ["superseded_by_issuance_id"]
            isOneToOne: false
            referencedRelation: "form_2307_issuances"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "form_2307_issuances_supersedes_issuance_id_fkey"
            columns: ["supersedes_issuance_id"]
            isOneToOne: false
            referencedRelation: "form_2307_issuances"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "form_2307_issuances_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
      form_2307_tracking: {
        Row: {
          atc_code_id: string | null
          claim_tax_quarter: number | null
          claim_tax_year: number | null
          claimed_at: string | null
          claimed_by: string | null
          company_id: string
          created_at: string
          created_by: string | null
          customer_id: string | null
          cwt_amount_booked: number
          date_received: string | null
          file_url: string | null
          id: string
          invalidated_at: string | null
          invalidated_reason: string | null
          period_covered: string | null
          receipt_line_id: string
          remarks: string | null
          status: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          atc_code_id?: string | null
          claim_tax_quarter?: number | null
          claim_tax_year?: number | null
          claimed_at?: string | null
          claimed_by?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          customer_id?: string | null
          cwt_amount_booked?: number
          date_received?: string | null
          file_url?: string | null
          id?: string
          invalidated_at?: string | null
          invalidated_reason?: string | null
          period_covered?: string | null
          receipt_line_id: string
          remarks?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          atc_code_id?: string | null
          claim_tax_quarter?: number | null
          claim_tax_year?: number | null
          claimed_at?: string | null
          claimed_by?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          customer_id?: string | null
          cwt_amount_booked?: number
          date_received?: string | null
          file_url?: string | null
          id?: string
          invalidated_at?: string | null
          invalidated_reason?: string | null
          period_covered?: string | null
          receipt_line_id?: string
          remarks?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "form_2307_tracking_atc_code_id_fkey"
            columns: ["atc_code_id"]
            isOneToOne: false
            referencedRelation: "atc_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "form_2307_tracking_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "form_2307_tracking_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "form_2307_tracking_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "form_2307_tracking_receipt_line_id_fkey"
            columns: ["receipt_line_id"]
            isOneToOne: true
            referencedRelation: "receipt_lines"
            referencedColumns: ["id"]
          },
        ]
      }
      fs_structure: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          display_order: number
          id: string
          is_subtotal: boolean
          line_code: string
          line_label: string
          line_role: string
          parent_id: string | null
          statement: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          display_order?: number
          id?: string
          is_subtotal?: boolean
          line_code: string
          line_label: string
          line_role?: string
          parent_id?: string | null
          statement: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          display_order?: number
          id?: string
          is_subtotal?: boolean
          line_code?: string
          line_label?: string
          line_role?: string
          parent_id?: string | null
          statement?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fs_structure_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fs_structure_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "fs_structure_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "fs_structure"
            referencedColumns: ["id"]
          },
        ]
      }
      functional_entities: {
        Row: {
          branch_id: string | null
          company_id: string
          created_at: string
          created_by: string | null
          description: string | null
          entity_code: string
          entity_name: string
          functional_entity_type: string
          id: string
          is_active: boolean
          parent_functional_entity_id: string | null
          updated_at: string
          updated_by: string | null
          valid_from: string | null
          valid_to: string | null
        }
        Insert: {
          branch_id?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          entity_code: string
          entity_name: string
          functional_entity_type?: string
          id?: string
          is_active?: boolean
          parent_functional_entity_id?: string | null
          updated_at?: string
          updated_by?: string | null
          valid_from?: string | null
          valid_to?: string | null
        }
        Update: {
          branch_id?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          entity_code?: string
          entity_name?: string
          functional_entity_type?: string
          id?: string
          is_active?: boolean
          parent_functional_entity_id?: string | null
          updated_at?: string
          updated_by?: string | null
          valid_from?: string | null
          valid_to?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "functional_entities_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "functional_entities_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "functional_entities_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "functional_entities_parent_functional_entity_id_fkey"
            columns: ["parent_functional_entity_id"]
            isOneToOne: false
            referencedRelation: "functional_entities"
            referencedColumns: ["id"]
          },
        ]
      }
      fund_transfers: {
        Row: {
          amount: number
          branch_id: string | null
          company_id: string
          created_at: string
          created_by: string | null
          fiscal_period_id: string | null
          from_account_id: string
          ft_number: string
          id: string
          journal_entry_id: string | null
          posted_at: string | null
          posted_by: string | null
          reference_number: string | null
          remarks: string | null
          status: string
          to_account_id: string
          transfer_date: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          amount: number
          branch_id?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          fiscal_period_id?: string | null
          from_account_id: string
          ft_number: string
          id?: string
          journal_entry_id?: string | null
          posted_at?: string | null
          posted_by?: string | null
          reference_number?: string | null
          remarks?: string | null
          status?: string
          to_account_id: string
          transfer_date: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          amount?: number
          branch_id?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          fiscal_period_id?: string | null
          from_account_id?: string
          ft_number?: string
          id?: string
          journal_entry_id?: string | null
          posted_at?: string | null
          posted_by?: string | null
          reference_number?: string | null
          remarks?: string | null
          status?: string
          to_account_id?: string
          transfer_date?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fund_transfers_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fund_transfers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fund_transfers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "fund_transfers_fiscal_period_id_fkey"
            columns: ["fiscal_period_id"]
            isOneToOne: false
            referencedRelation: "fiscal_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fund_transfers_from_account_id_fkey"
            columns: ["from_account_id"]
            isOneToOne: false
            referencedRelation: "bank_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fund_transfers_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fund_transfers_to_account_id_fkey"
            columns: ["to_account_id"]
            isOneToOne: false
            referencedRelation: "bank_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      fwt_returns: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          filed_date: string | null
          id: string
          period_quarter: number
          period_year: number
          reference_no: string | null
          remarks: string | null
          remitted_prior: number
          status: string
          still_due: number
          total_fwt_withheld: number
          total_tax_base: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          filed_date?: string | null
          id?: string
          period_quarter: number
          period_year: number
          reference_no?: string | null
          remarks?: string | null
          remitted_prior?: number
          status?: string
          still_due?: number
          total_fwt_withheld?: number
          total_tax_base?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          filed_date?: string | null
          id?: string
          period_quarter?: number
          period_year?: number
          reference_no?: string | null
          remarks?: string | null
          remitted_prior?: number
          status?: string
          still_due?: number
          total_fwt_withheld?: number
          total_tax_base?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fwt_returns_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fwt_returns_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      goods_issue_lines: {
        Row: {
          company_id: string
          gl_expense_account_id: string | null
          id: string
          inventory_cost_layer_id: string | null
          inventory_transaction_id: string | null
          issue_id: string
          item_id: string
          lot_number: string | null
          qty_issued: number
          serial_number: string | null
          total_cost: number
          unit_cost: number
        }
        Insert: {
          company_id: string
          gl_expense_account_id?: string | null
          id?: string
          inventory_cost_layer_id?: string | null
          inventory_transaction_id?: string | null
          issue_id: string
          item_id: string
          lot_number?: string | null
          qty_issued: number
          serial_number?: string | null
          total_cost?: number
          unit_cost?: number
        }
        Update: {
          company_id?: string
          gl_expense_account_id?: string | null
          id?: string
          inventory_cost_layer_id?: string | null
          inventory_transaction_id?: string | null
          issue_id?: string
          item_id?: string
          lot_number?: string | null
          qty_issued?: number
          serial_number?: string | null
          total_cost?: number
          unit_cost?: number
        }
        Relationships: [
          {
            foreignKeyName: "goods_issue_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "goods_issue_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "goods_issue_lines_gl_expense_account_id_fkey"
            columns: ["gl_expense_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "goods_issue_lines_inventory_cost_layer_id_fkey"
            columns: ["inventory_cost_layer_id"]
            isOneToOne: false
            referencedRelation: "inventory_cost_layers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "goods_issue_lines_inventory_cost_layer_id_fkey"
            columns: ["inventory_cost_layer_id"]
            isOneToOne: false
            referencedRelation: "vw_available_inventory_identities"
            referencedColumns: ["inventory_cost_layer_id"]
          },
          {
            foreignKeyName: "goods_issue_lines_inventory_transaction_id_fkey"
            columns: ["inventory_transaction_id"]
            isOneToOne: false
            referencedRelation: "inventory_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "goods_issue_lines_issue_id_fkey"
            columns: ["issue_id"]
            isOneToOne: false
            referencedRelation: "goods_issues"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "goods_issue_lines_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
        ]
      }
      goods_issues: {
        Row: {
          branch_id: string | null
          company_id: string
          cost_center_id: string | null
          created_at: string
          created_by: string | null
          department_id: string | null
          fiscal_period_id: string | null
          functional_entity_id: string | null
          id: string
          issue_date: string
          issue_number: string
          journal_entry_id: string | null
          location_id: string | null
          notes: string | null
          posted_at: string | null
          posted_by: string | null
          project_id: string | null
          purpose: string | null
          status: string
          updated_at: string
          updated_by: string | null
          warehouse_id: string
        }
        Insert: {
          branch_id?: string | null
          company_id: string
          cost_center_id?: string | null
          created_at?: string
          created_by?: string | null
          department_id?: string | null
          fiscal_period_id?: string | null
          functional_entity_id?: string | null
          id?: string
          issue_date: string
          issue_number: string
          journal_entry_id?: string | null
          location_id?: string | null
          notes?: string | null
          posted_at?: string | null
          posted_by?: string | null
          project_id?: string | null
          purpose?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
          warehouse_id: string
        }
        Update: {
          branch_id?: string | null
          company_id?: string
          cost_center_id?: string | null
          created_at?: string
          created_by?: string | null
          department_id?: string | null
          fiscal_period_id?: string | null
          functional_entity_id?: string | null
          id?: string
          issue_date?: string
          issue_number?: string
          journal_entry_id?: string | null
          location_id?: string | null
          notes?: string | null
          posted_at?: string | null
          posted_by?: string | null
          project_id?: string | null
          purpose?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
          warehouse_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "goods_issues_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "goods_issues_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "goods_issues_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "goods_issues_cost_center_id_fkey"
            columns: ["cost_center_id"]
            isOneToOne: false
            referencedRelation: "cost_centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "goods_issues_department_id_fkey"
            columns: ["department_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "goods_issues_fiscal_period_id_fkey"
            columns: ["fiscal_period_id"]
            isOneToOne: false
            referencedRelation: "fiscal_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "goods_issues_functional_entity_id_fkey"
            columns: ["functional_entity_id"]
            isOneToOne: false
            referencedRelation: "functional_entities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "goods_issues_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "goods_issues_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "goods_issues_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "goods_issues_warehouse_id_fkey"
            columns: ["warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
        ]
      }
      income_tax_computations: {
        Row: {
          allowable_deductions: number
          company_id: string
          created_at: string
          created_by: string | null
          deduction_method: string
          gross_income: number
          id: string
          period_quarter: number | null
          period_type: string
          period_year: number
          remarks: string | null
          status: string
          tax_due: number
          tax_rate: number
          taxable_income: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          allowable_deductions?: number
          company_id: string
          created_at?: string
          created_by?: string | null
          deduction_method: string
          gross_income?: number
          id?: string
          period_quarter?: number | null
          period_type: string
          period_year: number
          remarks?: string | null
          status?: string
          tax_due?: number
          tax_rate?: number
          taxable_income?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          allowable_deductions?: number
          company_id?: string
          created_at?: string
          created_by?: string | null
          deduction_method?: string
          gross_income?: number
          id?: string
          period_quarter?: number | null
          period_type?: string
          period_year?: number
          remarks?: string | null
          status?: string
          tax_due?: number
          tax_rate?: number
          taxable_income?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "income_tax_computations_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "income_tax_computations_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      inter_branch_transfers: {
        Row: {
          amount: number
          company_id: string
          created_at: string
          created_by: string | null
          fiscal_period_id: string | null
          from_account_id: string | null
          from_branch_id: string
          ibt_number: string
          id: string
          intercompany_account_id: string | null
          journal_entry_id: string | null
          posted_at: string | null
          posted_by: string | null
          reference_number: string | null
          remarks: string | null
          status: string
          to_account_id: string | null
          to_branch_id: string
          transfer_date: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          amount: number
          company_id: string
          created_at?: string
          created_by?: string | null
          fiscal_period_id?: string | null
          from_account_id?: string | null
          from_branch_id: string
          ibt_number: string
          id?: string
          intercompany_account_id?: string | null
          journal_entry_id?: string | null
          posted_at?: string | null
          posted_by?: string | null
          reference_number?: string | null
          remarks?: string | null
          status?: string
          to_account_id?: string | null
          to_branch_id: string
          transfer_date: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          amount?: number
          company_id?: string
          created_at?: string
          created_by?: string | null
          fiscal_period_id?: string | null
          from_account_id?: string | null
          from_branch_id?: string
          ibt_number?: string
          id?: string
          intercompany_account_id?: string | null
          journal_entry_id?: string | null
          posted_at?: string | null
          posted_by?: string | null
          reference_number?: string | null
          remarks?: string | null
          status?: string
          to_account_id?: string | null
          to_branch_id?: string
          transfer_date?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "inter_branch_transfers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inter_branch_transfers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "inter_branch_transfers_fiscal_period_id_fkey"
            columns: ["fiscal_period_id"]
            isOneToOne: false
            referencedRelation: "fiscal_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inter_branch_transfers_from_account_id_fkey"
            columns: ["from_account_id"]
            isOneToOne: false
            referencedRelation: "bank_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inter_branch_transfers_from_branch_id_fkey"
            columns: ["from_branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inter_branch_transfers_intercompany_account_id_fkey"
            columns: ["intercompany_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inter_branch_transfers_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inter_branch_transfers_to_account_id_fkey"
            columns: ["to_account_id"]
            isOneToOne: false
            referencedRelation: "bank_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inter_branch_transfers_to_branch_id_fkey"
            columns: ["to_branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
        ]
      }
      inventory_accounting_profiles: {
        Row: {
          accounting_framework: string
          activation_state: string
          company_id: string
          created_at: string
          created_by: string
          effective_from: string
          effective_to: string | null
          id: string
          precision_policy_id: string
          profile_code: string
          version_no: number
        }
        Insert: {
          accounting_framework?: string
          activation_state?: string
          company_id: string
          created_at?: string
          created_by: string
          effective_from: string
          effective_to?: string | null
          id?: string
          precision_policy_id: string
          profile_code: string
          version_no: number
        }
        Update: {
          accounting_framework?: string
          activation_state?: string
          company_id?: string
          created_at?: string
          created_by?: string
          effective_from?: string
          effective_to?: string | null
          id?: string
          precision_policy_id?: string
          profile_code?: string
          version_no?: number
        }
        Relationships: [
          {
            foreignKeyName: "inventory_accounting_profiles_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_accounting_profiles_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "inventory_accounting_profiles_precision_policy_id_fkey"
            columns: ["precision_policy_id"]
            isOneToOne: false
            referencedRelation: "inventory_precision_policies"
            referencedColumns: ["id"]
          },
        ]
      }
      inventory_canonical_form_versions: {
        Row: {
          activated_from: string
          activated_to: string | null
          activation_state: string
          company_id: string
          created_at: string
          created_by: string
          digest_algorithm: string
          encoding_rules: Json
          id: string
          version_code: string
        }
        Insert: {
          activated_from: string
          activated_to?: string | null
          activation_state?: string
          company_id: string
          created_at?: string
          created_by: string
          digest_algorithm?: string
          encoding_rules?: Json
          id?: string
          version_code: string
        }
        Update: {
          activated_from?: string
          activated_to?: string | null
          activation_state?: string
          company_id?: string
          created_at?: string
          created_by?: string
          digest_algorithm?: string
          encoding_rules?: Json
          id?: string
          version_code?: string
        }
        Relationships: [
          {
            foreignKeyName: "inventory_canonical_form_versions_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_canonical_form_versions_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      inventory_correction_graph_versions: {
        Row: {
          activation_state: string
          anchoring_semantics: Json
          commutativity_proofs: Json
          company_id: string
          created_at: string
          created_by: string
          effective_from: string
          effective_to: string | null
          id: string
          version_no: number
        }
        Insert: {
          activation_state?: string
          anchoring_semantics?: Json
          commutativity_proofs?: Json
          company_id: string
          created_at?: string
          created_by: string
          effective_from: string
          effective_to?: string | null
          id?: string
          version_no: number
        }
        Update: {
          activation_state?: string
          anchoring_semantics?: Json
          commutativity_proofs?: Json
          company_id?: string
          created_at?: string
          created_by?: string
          effective_from?: string
          effective_to?: string | null
          id?: string
          version_no?: number
        }
        Relationships: [
          {
            foreignKeyName: "inventory_correction_graph_versions_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_correction_graph_versions_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      inventory_cost_formula_policies: {
        Row: {
          accounting_profile_id: string
          activation_state: string
          allowed_scope_type: string
          company_id: string
          costing_method: string
          created_at: string
          created_by: string
          effective_from: string
          effective_to: string | null
          id: string
          method_change_classification: string
          policy_group_code: string
          transition_evidence: Json
          transition_from_policy_id: string | null
          version_no: number
        }
        Insert: {
          accounting_profile_id: string
          activation_state?: string
          allowed_scope_type: string
          company_id: string
          costing_method: string
          created_at?: string
          created_by: string
          effective_from: string
          effective_to?: string | null
          id?: string
          method_change_classification?: string
          policy_group_code: string
          transition_evidence?: Json
          transition_from_policy_id?: string | null
          version_no: number
        }
        Update: {
          accounting_profile_id?: string
          activation_state?: string
          allowed_scope_type?: string
          company_id?: string
          costing_method?: string
          created_at?: string
          created_by?: string
          effective_from?: string
          effective_to?: string | null
          id?: string
          method_change_classification?: string
          policy_group_code?: string
          transition_evidence?: Json
          transition_from_policy_id?: string | null
          version_no?: number
        }
        Relationships: [
          {
            foreignKeyName: "inventory_cost_formula_policies_accounting_profile_id_fkey"
            columns: ["accounting_profile_id"]
            isOneToOne: false
            referencedRelation: "inventory_accounting_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_cost_formula_policies_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_cost_formula_policies_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "inventory_cost_formula_policies_transition_from_policy_id_fkey"
            columns: ["transition_from_policy_id"]
            isOneToOne: false
            referencedRelation: "inventory_cost_formula_policies"
            referencedColumns: ["id"]
          },
        ]
      }
      inventory_cost_layers: {
        Row: {
          company_id: string
          created_at: string
          id: string
          is_exhausted: boolean
          item_id: string
          layer_date: string
          lot_number: string | null
          origin_inventory_transaction_id: string | null
          original_qty: number
          original_value: number
          parent_layer_id: string | null
          qty_remaining: number
          reference_doc_id: string | null
          reference_doc_type: string | null
          remaining_value: number
          serial_number: string | null
          source_line_id: string | null
          unit_cost: number
          voided_by_inventory_transaction_id: string | null
          warehouse_id: string
        }
        Insert: {
          company_id: string
          created_at?: string
          id?: string
          is_exhausted?: boolean
          item_id: string
          layer_date: string
          lot_number?: string | null
          origin_inventory_transaction_id?: string | null
          original_qty: number
          original_value: number
          parent_layer_id?: string | null
          qty_remaining: number
          reference_doc_id?: string | null
          reference_doc_type?: string | null
          remaining_value: number
          serial_number?: string | null
          source_line_id?: string | null
          unit_cost?: number
          voided_by_inventory_transaction_id?: string | null
          warehouse_id: string
        }
        Update: {
          company_id?: string
          created_at?: string
          id?: string
          is_exhausted?: boolean
          item_id?: string
          layer_date?: string
          lot_number?: string | null
          origin_inventory_transaction_id?: string | null
          original_qty?: number
          original_value?: number
          parent_layer_id?: string | null
          qty_remaining?: number
          reference_doc_id?: string | null
          reference_doc_type?: string | null
          remaining_value?: number
          serial_number?: string | null
          source_line_id?: string | null
          unit_cost?: number
          voided_by_inventory_transaction_id?: string | null
          warehouse_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "inventory_cost_layers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_cost_layers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "inventory_cost_layers_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_cost_layers_origin_inventory_transaction_id_fkey"
            columns: ["origin_inventory_transaction_id"]
            isOneToOne: false
            referencedRelation: "inventory_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_cost_layers_parent_layer_id_fkey"
            columns: ["parent_layer_id"]
            isOneToOne: false
            referencedRelation: "inventory_cost_layers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_cost_layers_parent_layer_id_fkey"
            columns: ["parent_layer_id"]
            isOneToOne: false
            referencedRelation: "vw_available_inventory_identities"
            referencedColumns: ["inventory_cost_layer_id"]
          },
          {
            foreignKeyName: "inventory_cost_layers_voided_by_inventory_transaction_id_fkey"
            columns: ["voided_by_inventory_transaction_id"]
            isOneToOne: false
            referencedRelation: "inventory_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_cost_layers_warehouse_id_fkey"
            columns: ["warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
        ]
      }
      inventory_costing_pending_allocations: {
        Row: {
          batch_id: string
          layer_id: string
          quantity: number
          total_cost: number
          unit_cost: number
        }
        Insert: {
          batch_id: string
          layer_id: string
          quantity: number
          total_cost: number
          unit_cost: number
        }
        Update: {
          batch_id?: string
          layer_id?: string
          quantity?: number
          total_cost?: number
          unit_cost?: number
        }
        Relationships: [
          {
            foreignKeyName: "inventory_costing_pending_allocations_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "inventory_costing_pending_batches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_costing_pending_allocations_layer_id_fkey"
            columns: ["layer_id"]
            isOneToOne: false
            referencedRelation: "inventory_cost_layers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_costing_pending_allocations_layer_id_fkey"
            columns: ["layer_id"]
            isOneToOne: false
            referencedRelation: "vw_available_inventory_identities"
            referencedColumns: ["inventory_cost_layer_id"]
          },
        ]
      }
      inventory_costing_pending_batches: {
        Row: {
          backend_pid: number
          company_id: string
          created_at: string
          id: string
          item_id: string
          local_txid: number
          quantity: number
          source_line_id: string | null
          total_cost: number
          warehouse_id: string
        }
        Insert: {
          backend_pid: number
          company_id: string
          created_at?: string
          id?: string
          item_id: string
          local_txid: number
          quantity: number
          source_line_id?: string | null
          total_cost: number
          warehouse_id: string
        }
        Update: {
          backend_pid?: number
          company_id?: string
          created_at?: string
          id?: string
          item_id?: string
          local_txid?: number
          quantity?: number
          source_line_id?: string | null
          total_cost?: number
          warehouse_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "inventory_costing_pending_batches_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_costing_pending_batches_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "inventory_costing_pending_batches_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_costing_pending_batches_warehouse_id_fkey"
            columns: ["warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
        ]
      }
      inventory_costing_runtime_queue: {
        Row: {
          backend_pid: number
          company_id: string
          created_at: string
          id: string
          inventory_cost_layer_id: string | null
          item_id: string
          layers_restored: boolean
          local_txid: number
          lot_number: string | null
          operation: string
          original_transaction_id: string | null
          selection_consumed: boolean
          sequence_no: number
          serial_number: string | null
          source_line_id: string | null
          warehouse_id: string
        }
        Insert: {
          backend_pid: number
          company_id: string
          created_at?: string
          id?: string
          inventory_cost_layer_id?: string | null
          item_id: string
          layers_restored?: boolean
          local_txid: number
          lot_number?: string | null
          operation: string
          original_transaction_id?: string | null
          selection_consumed?: boolean
          sequence_no: number
          serial_number?: string | null
          source_line_id?: string | null
          warehouse_id: string
        }
        Update: {
          backend_pid?: number
          company_id?: string
          created_at?: string
          id?: string
          inventory_cost_layer_id?: string | null
          item_id?: string
          layers_restored?: boolean
          local_txid?: number
          lot_number?: string | null
          operation?: string
          original_transaction_id?: string | null
          selection_consumed?: boolean
          sequence_no?: number
          serial_number?: string | null
          source_line_id?: string | null
          warehouse_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "inventory_costing_runtime_queue_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_costing_runtime_queue_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "inventory_costing_runtime_queue_inventory_cost_layer_id_fkey"
            columns: ["inventory_cost_layer_id"]
            isOneToOne: false
            referencedRelation: "inventory_cost_layers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_costing_runtime_queue_inventory_cost_layer_id_fkey"
            columns: ["inventory_cost_layer_id"]
            isOneToOne: false
            referencedRelation: "vw_available_inventory_identities"
            referencedColumns: ["inventory_cost_layer_id"]
          },
          {
            foreignKeyName: "inventory_costing_runtime_queue_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_costing_runtime_queue_original_transaction_id_fkey"
            columns: ["original_transaction_id"]
            isOneToOne: false
            referencedRelation: "inventory_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_costing_runtime_queue_warehouse_id_fkey"
            columns: ["warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
        ]
      }
      inventory_event_allocations: {
        Row: {
          allocation_evidence: Json
          allocation_key: string
          allocation_sequence: number
          authoritative_valuation_amount: number
          company_id: string
          created_at: string
          created_by: string
          gl_basis_amount: number
          id: string
          inventory_event_value_id: string
          is_final_allocation: boolean
          residual_rank: number
          residual_units: number
        }
        Insert: {
          allocation_evidence: Json
          allocation_key: string
          allocation_sequence: number
          authoritative_valuation_amount: number
          company_id: string
          created_at?: string
          created_by: string
          gl_basis_amount: number
          id?: string
          inventory_event_value_id: string
          is_final_allocation?: boolean
          residual_rank: number
          residual_units?: number
        }
        Update: {
          allocation_evidence?: Json
          allocation_key?: string
          allocation_sequence?: number
          authoritative_valuation_amount?: number
          company_id?: string
          created_at?: string
          created_by?: string
          gl_basis_amount?: number
          id?: string
          inventory_event_value_id?: string
          is_final_allocation?: boolean
          residual_rank?: number
          residual_units?: number
        }
        Relationships: [
          {
            foreignKeyName: "inventory_event_allocations_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_event_allocations_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "inventory_event_allocations_inventory_event_value_id_fkey"
            columns: ["inventory_event_value_id"]
            isOneToOne: false
            referencedRelation: "inventory_event_values"
            referencedColumns: ["id"]
          },
        ]
      }
      inventory_event_effect_ranks: {
        Row: {
          activation_state: string
          company_id: string
          created_at: string
          created_by: string
          effect_class: string
          effect_rank: number
          id: string
          order_policy_id: string
        }
        Insert: {
          activation_state?: string
          company_id: string
          created_at?: string
          created_by: string
          effect_class: string
          effect_rank: number
          id?: string
          order_policy_id: string
        }
        Update: {
          activation_state?: string
          company_id?: string
          created_at?: string
          created_by?: string
          effect_class?: string
          effect_rank?: number
          id?: string
          order_policy_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "inventory_event_effect_ranks_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_event_effect_ranks_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "inventory_event_effect_ranks_order_policy_id_fkey"
            columns: ["order_policy_id"]
            isOneToOne: false
            referencedRelation: "inventory_event_order_policies"
            referencedColumns: ["id"]
          },
        ]
      }
      inventory_event_order_keys: {
        Row: {
          canonical_form_version_id: string
          canonical_key_bytes: string
          canonical_source_identity: string
          company_id: string
          correction_approved_at: string
          correction_chain_depth: number
          correction_effective_at: string
          correction_graph_version_id: string
          correction_identity: string
          correction_placement_class: string
          correction_root_event_id: string | null
          created_at: string
          created_by: string
          document_order_key: string
          ecc_key_digest: string
          economic_effect_class: string
          economic_effect_rank: number
          economic_effective_at: string
          event_ordinal: number
          id: string
          inventory_event_id: string
          occurrence_ordinal: number
          order_policy_version_id: string
          registry_source_document_type: string
          resolution_state: string
          scope_resolution_version_id: string
          source_line_ordinal: number
          source_precision_code: string
          source_type_rank: number
          transition_rank: number
          valuation_stream_id: string
        }
        Insert: {
          canonical_form_version_id: string
          canonical_key_bytes: string
          canonical_source_identity: string
          company_id: string
          correction_approved_at: string
          correction_chain_depth: number
          correction_effective_at: string
          correction_graph_version_id: string
          correction_identity: string
          correction_placement_class: string
          correction_root_event_id?: string | null
          created_at?: string
          created_by: string
          document_order_key: string
          ecc_key_digest: string
          economic_effect_class: string
          economic_effect_rank: number
          economic_effective_at: string
          event_ordinal: number
          id?: string
          inventory_event_id: string
          occurrence_ordinal: number
          order_policy_version_id: string
          registry_source_document_type: string
          resolution_state?: string
          scope_resolution_version_id: string
          source_line_ordinal: number
          source_precision_code: string
          source_type_rank: number
          transition_rank: number
          valuation_stream_id: string
        }
        Update: {
          canonical_form_version_id?: string
          canonical_key_bytes?: string
          canonical_source_identity?: string
          company_id?: string
          correction_approved_at?: string
          correction_chain_depth?: number
          correction_effective_at?: string
          correction_graph_version_id?: string
          correction_identity?: string
          correction_placement_class?: string
          correction_root_event_id?: string | null
          created_at?: string
          created_by?: string
          document_order_key?: string
          ecc_key_digest?: string
          economic_effect_class?: string
          economic_effect_rank?: number
          economic_effective_at?: string
          event_ordinal?: number
          id?: string
          inventory_event_id?: string
          occurrence_ordinal?: number
          order_policy_version_id?: string
          registry_source_document_type?: string
          resolution_state?: string
          scope_resolution_version_id?: string
          source_line_ordinal?: number
          source_precision_code?: string
          source_type_rank?: number
          transition_rank?: number
          valuation_stream_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "inventory_event_order_keys_canonical_form_version_id_fkey"
            columns: ["canonical_form_version_id"]
            isOneToOne: false
            referencedRelation: "inventory_canonical_form_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_event_order_keys_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_event_order_keys_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "inventory_event_order_keys_correction_graph_version_id_fkey"
            columns: ["correction_graph_version_id"]
            isOneToOne: false
            referencedRelation: "inventory_correction_graph_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_event_order_keys_correction_root_event_id_fkey"
            columns: ["correction_root_event_id"]
            isOneToOne: false
            referencedRelation: "inventory_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_event_order_keys_inventory_event_id_fkey"
            columns: ["inventory_event_id"]
            isOneToOne: false
            referencedRelation: "inventory_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_event_order_keys_order_policy_version_id_fkey"
            columns: ["order_policy_version_id"]
            isOneToOne: false
            referencedRelation: "inventory_event_order_policies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_event_order_keys_registry_source_document_type_fkey"
            columns: ["registry_source_document_type"]
            isOneToOne: false
            referencedRelation: "ref_inventory_event_source_types"
            referencedColumns: ["source_document_type"]
          },
          {
            foreignKeyName: "inventory_event_order_keys_scope_resolution_version_id_fkey"
            columns: ["scope_resolution_version_id"]
            isOneToOne: false
            referencedRelation: "inventory_valuation_scopes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_event_order_keys_valuation_stream_id_fkey"
            columns: ["valuation_stream_id"]
            isOneToOne: false
            referencedRelation: "inventory_valuation_streams"
            referencedColumns: ["id"]
          },
        ]
      }
      inventory_event_order_policies: {
        Row: {
          activation_state: string
          company_id: string
          created_at: string
          created_by: string
          effective_from: string
          effective_to: string | null
          id: string
          policy_code: string
          version_no: number
        }
        Insert: {
          activation_state?: string
          company_id: string
          created_at?: string
          created_by: string
          effective_from: string
          effective_to?: string | null
          id?: string
          policy_code: string
          version_no: number
        }
        Update: {
          activation_state?: string
          company_id?: string
          created_at?: string
          created_by?: string
          effective_from?: string
          effective_to?: string | null
          id?: string
          policy_code?: string
          version_no?: number
        }
        Relationships: [
          {
            foreignKeyName: "inventory_event_order_policies_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_event_order_policies_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      inventory_event_source_links: {
        Row: {
          company_id: string
          created_at: string
          created_by: string
          id: string
          immutable_relationship_evidence: Json
          inventory_event_id: string
          related_inventory_event_id: string | null
          relationship_type: string
          source_document_id: string
          source_document_type: string
          source_line_id: string
          source_occurrence_sequence: number
          source_transition: string
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by: string
          id?: string
          immutable_relationship_evidence: Json
          inventory_event_id: string
          related_inventory_event_id?: string | null
          relationship_type: string
          source_document_id: string
          source_document_type: string
          source_line_id: string
          source_occurrence_sequence: number
          source_transition: string
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string
          id?: string
          immutable_relationship_evidence?: Json
          inventory_event_id?: string
          related_inventory_event_id?: string | null
          relationship_type?: string
          source_document_id?: string
          source_document_type?: string
          source_line_id?: string
          source_occurrence_sequence?: number
          source_transition?: string
        }
        Relationships: [
          {
            foreignKeyName: "inventory_event_source_links_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_event_source_links_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "inventory_event_source_links_inventory_event_id_fkey"
            columns: ["inventory_event_id"]
            isOneToOne: false
            referencedRelation: "inventory_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_event_source_links_related_inventory_event_id_fkey"
            columns: ["related_inventory_event_id"]
            isOneToOne: false
            referencedRelation: "inventory_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_event_source_links_source_document_type_fkey"
            columns: ["source_document_type"]
            isOneToOne: false
            referencedRelation: "ref_inventory_event_source_types"
            referencedColumns: ["source_document_type"]
          },
        ]
      }
      inventory_event_values: {
        Row: {
          authoritative_functional_amount: number
          authoritative_transaction_amount: number
          calculation_evidence: Json
          company_id: string
          created_at: string
          created_by: string
          derived_unit_rate: number | null
          exchange_rate_identity: string | null
          functional_currency_code: string
          functional_currency_scale: number
          gl_basis_amount: number
          id: string
          inventory_event_id: string
          residual_units: number
          transaction_currency_code: string
          transaction_currency_scale: number
          unit_rate_scale: number
          valuation_amount_scale: number
          value_role: string
        }
        Insert: {
          authoritative_functional_amount: number
          authoritative_transaction_amount: number
          calculation_evidence: Json
          company_id: string
          created_at?: string
          created_by: string
          derived_unit_rate?: number | null
          exchange_rate_identity?: string | null
          functional_currency_code: string
          functional_currency_scale: number
          gl_basis_amount: number
          id?: string
          inventory_event_id: string
          residual_units?: number
          transaction_currency_code: string
          transaction_currency_scale: number
          unit_rate_scale?: number
          valuation_amount_scale?: number
          value_role: string
        }
        Update: {
          authoritative_functional_amount?: number
          authoritative_transaction_amount?: number
          calculation_evidence?: Json
          company_id?: string
          created_at?: string
          created_by?: string
          derived_unit_rate?: number | null
          exchange_rate_identity?: string | null
          functional_currency_code?: string
          functional_currency_scale?: number
          gl_basis_amount?: number
          id?: string
          inventory_event_id?: string
          residual_units?: number
          transaction_currency_code?: string
          transaction_currency_scale?: number
          unit_rate_scale?: number
          valuation_amount_scale?: number
          value_role?: string
        }
        Relationships: [
          {
            foreignKeyName: "inventory_event_values_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_event_values_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "inventory_event_values_inventory_event_id_fkey"
            columns: ["inventory_event_id"]
            isOneToOne: false
            referencedRelation: "inventory_events"
            referencedColumns: ["id"]
          },
        ]
      }
      inventory_events: {
        Row: {
          accounting_date: string | null
          accounting_profile_id: string
          base_quantity: number
          base_uom_id: string
          company_id: string
          correction_of_event_id: string | null
          cost_formula_policy_id: string
          costing_method: string
          created_at: string
          created_by: string
          effective_at: string
          event_effect: string
          event_sequence: number
          event_type: string
          foundation_state: string
          id: string
          immutable_source_evidence: Json
          item_id: string
          journal_entry_id: string | null
          lot_number: string | null
          occurrence_date: string
          occurrence_id: string
          physical_location_id: string | null
          physical_warehouse_id: string | null
          precision_policy_id: string
          predecessor_event_id: string | null
          reason_code: string
          reversal_of_event_id: string | null
          scope_sequence: number
          serial_number: string | null
          source_document_id: string
          source_document_type: string
          source_evidence_fingerprint: string
          source_line_id: string
          source_occurrence_sequence: number
          source_quantity: number
          source_transition: string
          source_uom_id: string
          uom_conversion_factor: number
          valuation_currency_code: string
          valuation_scope_id: string
        }
        Insert: {
          accounting_date?: string | null
          accounting_profile_id: string
          base_quantity: number
          base_uom_id: string
          company_id: string
          correction_of_event_id?: string | null
          cost_formula_policy_id: string
          costing_method: string
          created_at?: string
          created_by: string
          effective_at: string
          event_effect: string
          event_sequence: number
          event_type: string
          foundation_state?: string
          id?: string
          immutable_source_evidence: Json
          item_id: string
          journal_entry_id?: string | null
          lot_number?: string | null
          occurrence_date: string
          occurrence_id: string
          physical_location_id?: string | null
          physical_warehouse_id?: string | null
          precision_policy_id: string
          predecessor_event_id?: string | null
          reason_code: string
          reversal_of_event_id?: string | null
          scope_sequence: number
          serial_number?: string | null
          source_document_id: string
          source_document_type: string
          source_evidence_fingerprint: string
          source_line_id: string
          source_occurrence_sequence: number
          source_quantity: number
          source_transition: string
          source_uom_id: string
          uom_conversion_factor: number
          valuation_currency_code: string
          valuation_scope_id: string
        }
        Update: {
          accounting_date?: string | null
          accounting_profile_id?: string
          base_quantity?: number
          base_uom_id?: string
          company_id?: string
          correction_of_event_id?: string | null
          cost_formula_policy_id?: string
          costing_method?: string
          created_at?: string
          created_by?: string
          effective_at?: string
          event_effect?: string
          event_sequence?: number
          event_type?: string
          foundation_state?: string
          id?: string
          immutable_source_evidence?: Json
          item_id?: string
          journal_entry_id?: string | null
          lot_number?: string | null
          occurrence_date?: string
          occurrence_id?: string
          physical_location_id?: string | null
          physical_warehouse_id?: string | null
          precision_policy_id?: string
          predecessor_event_id?: string | null
          reason_code?: string
          reversal_of_event_id?: string | null
          scope_sequence?: number
          serial_number?: string | null
          source_document_id?: string
          source_document_type?: string
          source_evidence_fingerprint?: string
          source_line_id?: string
          source_occurrence_sequence?: number
          source_quantity?: number
          source_transition?: string
          source_uom_id?: string
          uom_conversion_factor?: number
          valuation_currency_code?: string
          valuation_scope_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "inventory_events_accounting_profile_id_fkey"
            columns: ["accounting_profile_id"]
            isOneToOne: false
            referencedRelation: "inventory_accounting_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_events_base_uom_id_fkey"
            columns: ["base_uom_id"]
            isOneToOne: false
            referencedRelation: "units_of_measure"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_events_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_events_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "inventory_events_correction_of_event_id_fkey"
            columns: ["correction_of_event_id"]
            isOneToOne: false
            referencedRelation: "inventory_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_events_cost_formula_policy_id_fkey"
            columns: ["cost_formula_policy_id"]
            isOneToOne: false
            referencedRelation: "inventory_cost_formula_policies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_events_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_events_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_events_occurrence_id_fkey"
            columns: ["occurrence_id"]
            isOneToOne: false
            referencedRelation: "inventory_occurrences"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_events_physical_location_id_fkey"
            columns: ["physical_location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_events_physical_warehouse_id_fkey"
            columns: ["physical_warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_events_precision_policy_id_fkey"
            columns: ["precision_policy_id"]
            isOneToOne: false
            referencedRelation: "inventory_precision_policies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_events_predecessor_event_id_fkey"
            columns: ["predecessor_event_id"]
            isOneToOne: false
            referencedRelation: "inventory_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_events_reversal_of_event_id_fkey"
            columns: ["reversal_of_event_id"]
            isOneToOne: false
            referencedRelation: "inventory_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_events_source_document_type_fkey"
            columns: ["source_document_type"]
            isOneToOne: false
            referencedRelation: "ref_inventory_event_source_types"
            referencedColumns: ["source_document_type"]
          },
          {
            foreignKeyName: "inventory_events_source_uom_id_fkey"
            columns: ["source_uom_id"]
            isOneToOne: false
            referencedRelation: "units_of_measure"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_events_valuation_scope_id_fkey"
            columns: ["valuation_scope_id"]
            isOneToOne: false
            referencedRelation: "inventory_valuation_scopes"
            referencedColumns: ["id"]
          },
        ]
      }
      inventory_layer_allocations: {
        Row: {
          allocation_kind: string
          company_id: string
          created_at: string
          id: string
          inventory_transaction_id: string
          layer_id: string
          quantity: number
          total_cost: number
          unit_cost: number
        }
        Insert: {
          allocation_kind: string
          company_id: string
          created_at?: string
          id?: string
          inventory_transaction_id: string
          layer_id: string
          quantity: number
          total_cost: number
          unit_cost: number
        }
        Update: {
          allocation_kind?: string
          company_id?: string
          created_at?: string
          id?: string
          inventory_transaction_id?: string
          layer_id?: string
          quantity?: number
          total_cost?: number
          unit_cost?: number
        }
        Relationships: [
          {
            foreignKeyName: "inventory_layer_allocations_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_layer_allocations_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "inventory_layer_allocations_inventory_transaction_id_fkey"
            columns: ["inventory_transaction_id"]
            isOneToOne: false
            referencedRelation: "inventory_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_layer_allocations_layer_id_fkey"
            columns: ["layer_id"]
            isOneToOne: false
            referencedRelation: "inventory_cost_layers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_layer_allocations_layer_id_fkey"
            columns: ["layer_id"]
            isOneToOne: false
            referencedRelation: "vw_available_inventory_identities"
            referencedColumns: ["inventory_cost_layer_id"]
          },
        ]
      }
      inventory_occurrences: {
        Row: {
          atomic_occurrence_id: string
          audit_identity: string
          company_id: string
          created_at: string
          created_by: string
          event_count: number
          event_ids: string[]
          failure_code: string | null
          failure_evidence: Json | null
          foundation_state: string
          id: string
          idempotency_key: string
          occurred_at: string
          occurrence_state: string
          posting_request_id: string | null
          posting_result_id: string | null
          projection_effect_count: number
          request_fingerprint: string
          retry_of_occurrence_id: string | null
          source_document_id: string
          source_document_type: string
          source_line_id: string
          source_occurrence_sequence: number
          source_transition: string
        }
        Insert: {
          atomic_occurrence_id: string
          audit_identity: string
          company_id: string
          created_at?: string
          created_by: string
          event_count?: number
          event_ids?: string[]
          failure_code?: string | null
          failure_evidence?: Json | null
          foundation_state?: string
          id?: string
          idempotency_key: string
          occurred_at: string
          occurrence_state: string
          posting_request_id?: string | null
          posting_result_id?: string | null
          projection_effect_count?: number
          request_fingerprint: string
          retry_of_occurrence_id?: string | null
          source_document_id: string
          source_document_type: string
          source_line_id: string
          source_occurrence_sequence: number
          source_transition: string
        }
        Update: {
          atomic_occurrence_id?: string
          audit_identity?: string
          company_id?: string
          created_at?: string
          created_by?: string
          event_count?: number
          event_ids?: string[]
          failure_code?: string | null
          failure_evidence?: Json | null
          foundation_state?: string
          id?: string
          idempotency_key?: string
          occurred_at?: string
          occurrence_state?: string
          posting_request_id?: string | null
          posting_result_id?: string | null
          projection_effect_count?: number
          request_fingerprint?: string
          retry_of_occurrence_id?: string | null
          source_document_id?: string
          source_document_type?: string
          source_line_id?: string
          source_occurrence_sequence?: number
          source_transition?: string
        }
        Relationships: [
          {
            foreignKeyName: "inventory_occurrences_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_occurrences_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "inventory_occurrences_retry_of_occurrence_id_fkey"
            columns: ["retry_of_occurrence_id"]
            isOneToOne: false
            referencedRelation: "inventory_occurrences"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_occurrences_source_document_type_fkey"
            columns: ["source_document_type"]
            isOneToOne: false
            referencedRelation: "ref_inventory_event_source_types"
            referencedColumns: ["source_document_type"]
          },
        ]
      }
      inventory_precision_policies: {
        Row: {
          activation_state: string
          company_id: string
          created_at: string
          created_by: string
          effective_from: string
          effective_to: string | null
          functional_currency_code: string
          functional_currency_scale: number
          gl_basis_scale: number
          id: string
          policy_code: string
          quantity_scale: number
          transaction_currency_code: string
          transaction_currency_scale: number
          unit_rate_scale: number
          valuation_amount_scale: number
          version_no: number
        }
        Insert: {
          activation_state?: string
          company_id: string
          created_at?: string
          created_by: string
          effective_from: string
          effective_to?: string | null
          functional_currency_code: string
          functional_currency_scale: number
          gl_basis_scale: number
          id?: string
          policy_code: string
          quantity_scale: number
          transaction_currency_code: string
          transaction_currency_scale: number
          unit_rate_scale?: number
          valuation_amount_scale?: number
          version_no: number
        }
        Update: {
          activation_state?: string
          company_id?: string
          created_at?: string
          created_by?: string
          effective_from?: string
          effective_to?: string | null
          functional_currency_code?: string
          functional_currency_scale?: number
          gl_basis_scale?: number
          id?: string
          policy_code?: string
          quantity_scale?: number
          transaction_currency_code?: string
          transaction_currency_scale?: number
          unit_rate_scale?: number
          valuation_amount_scale?: number
          version_no?: number
        }
        Relationships: [
          {
            foreignKeyName: "inventory_precision_policies_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_precision_policies_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      inventory_projection_versions: {
        Row: {
          company_id: string
          id: string
          projection_fingerprint: string
          projection_row_count: number
          projection_state: string
          projection_type: string
          rebuilt_at: string
          rebuilt_by: string
          replay_watermark_sequence: number
          source_event_count: number
          valuation_scope_id: string
        }
        Insert: {
          company_id: string
          id?: string
          projection_fingerprint: string
          projection_row_count: number
          projection_state?: string
          projection_type: string
          rebuilt_at?: string
          rebuilt_by: string
          replay_watermark_sequence: number
          source_event_count: number
          valuation_scope_id: string
        }
        Update: {
          company_id?: string
          id?: string
          projection_fingerprint?: string
          projection_row_count?: number
          projection_state?: string
          projection_type?: string
          rebuilt_at?: string
          rebuilt_by?: string
          replay_watermark_sequence?: number
          source_event_count?: number
          valuation_scope_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "inventory_projection_versions_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_projection_versions_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "inventory_projection_versions_valuation_scope_id_fkey"
            columns: ["valuation_scope_id"]
            isOneToOne: false
            referencedRelation: "inventory_valuation_scopes"
            referencedColumns: ["id"]
          },
        ]
      }
      inventory_source_type_ranks: {
        Row: {
          activation_state: string
          company_id: string
          created_at: string
          created_by: string
          id: string
          order_policy_id: string
          source_document_type: string
          source_type_rank: number
        }
        Insert: {
          activation_state?: string
          company_id: string
          created_at?: string
          created_by: string
          id?: string
          order_policy_id: string
          source_document_type: string
          source_type_rank: number
        }
        Update: {
          activation_state?: string
          company_id?: string
          created_at?: string
          created_by?: string
          id?: string
          order_policy_id?: string
          source_document_type?: string
          source_type_rank?: number
        }
        Relationships: [
          {
            foreignKeyName: "inventory_source_type_ranks_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_source_type_ranks_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "inventory_source_type_ranks_order_policy_id_fkey"
            columns: ["order_policy_id"]
            isOneToOne: false
            referencedRelation: "inventory_event_order_policies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_source_type_ranks_source_document_type_fkey"
            columns: ["source_document_type"]
            isOneToOne: false
            referencedRelation: "ref_inventory_event_source_types"
            referencedColumns: ["source_document_type"]
          },
        ]
      }
      inventory_transactions: {
        Row: {
          company_id: string
          costing_method: string | null
          created_at: string
          created_by: string | null
          functional_entity_id: string | null
          id: string
          item_id: string
          journal_entry_id: string | null
          location_id: string | null
          lot_number: string | null
          notes: string | null
          project_id: string | null
          qty: number
          qty_on_hand_after: number
          reference_doc_id: string | null
          reference_doc_type: string | null
          restores_inventory_transaction_id: string | null
          reversed_by_inventory_transaction_id: string | null
          reverses_inventory_transaction_id: string | null
          serial_number: string | null
          source_line_id: string | null
          total_cost: number
          transaction_date: string
          transaction_type: string
          unit_cost: number
          warehouse_id: string
        }
        Insert: {
          company_id: string
          costing_method?: string | null
          created_at?: string
          created_by?: string | null
          functional_entity_id?: string | null
          id?: string
          item_id: string
          journal_entry_id?: string | null
          location_id?: string | null
          lot_number?: string | null
          notes?: string | null
          project_id?: string | null
          qty: number
          qty_on_hand_after: number
          reference_doc_id?: string | null
          reference_doc_type?: string | null
          restores_inventory_transaction_id?: string | null
          reversed_by_inventory_transaction_id?: string | null
          reverses_inventory_transaction_id?: string | null
          serial_number?: string | null
          source_line_id?: string | null
          total_cost?: number
          transaction_date: string
          transaction_type: string
          unit_cost?: number
          warehouse_id: string
        }
        Update: {
          company_id?: string
          costing_method?: string | null
          created_at?: string
          created_by?: string | null
          functional_entity_id?: string | null
          id?: string
          item_id?: string
          journal_entry_id?: string | null
          location_id?: string | null
          lot_number?: string | null
          notes?: string | null
          project_id?: string | null
          qty?: number
          qty_on_hand_after?: number
          reference_doc_id?: string | null
          reference_doc_type?: string | null
          restores_inventory_transaction_id?: string | null
          reversed_by_inventory_transaction_id?: string | null
          reverses_inventory_transaction_id?: string | null
          serial_number?: string | null
          source_line_id?: string | null
          total_cost?: number
          transaction_date?: string
          transaction_type?: string
          unit_cost?: number
          warehouse_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "inventory_transactions_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_transactions_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "inventory_transactions_functional_entity_id_fkey"
            columns: ["functional_entity_id"]
            isOneToOne: false
            referencedRelation: "functional_entities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_transactions_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_transactions_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_transactions_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_transactions_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_transactions_restores_inventory_transaction_id_fkey"
            columns: ["restores_inventory_transaction_id"]
            isOneToOne: false
            referencedRelation: "inventory_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_transactions_reversed_by_inventory_transaction_i_fkey"
            columns: ["reversed_by_inventory_transaction_id"]
            isOneToOne: false
            referencedRelation: "inventory_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_transactions_reverses_inventory_transaction_id_fkey"
            columns: ["reverses_inventory_transaction_id"]
            isOneToOne: false
            referencedRelation: "inventory_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_transactions_warehouse_id_fkey"
            columns: ["warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
        ]
      }
      inventory_transition_ranks: {
        Row: {
          activation_state: string
          company_id: string
          created_at: string
          created_by: string
          id: string
          order_policy_id: string
          source_document_type: string
          source_transition: string
          transition_rank: number
        }
        Insert: {
          activation_state?: string
          company_id: string
          created_at?: string
          created_by: string
          id?: string
          order_policy_id: string
          source_document_type: string
          source_transition: string
          transition_rank: number
        }
        Update: {
          activation_state?: string
          company_id?: string
          created_at?: string
          created_by?: string
          id?: string
          order_policy_id?: string
          source_document_type?: string
          source_transition?: string
          transition_rank?: number
        }
        Relationships: [
          {
            foreignKeyName: "inventory_transition_ranks_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_transition_ranks_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "inventory_transition_ranks_order_policy_id_fkey"
            columns: ["order_policy_id"]
            isOneToOne: false
            referencedRelation: "inventory_event_order_policies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_transition_ranks_source_document_type_fkey"
            columns: ["source_document_type"]
            isOneToOne: false
            referencedRelation: "ref_inventory_event_source_types"
            referencedColumns: ["source_document_type"]
          },
        ]
      }
      inventory_valuation_scope_sequences: {
        Row: {
          company_id: string
          last_sequence: number
          updated_at: string
          valuation_scope_id: string
        }
        Insert: {
          company_id: string
          last_sequence?: number
          updated_at?: string
          valuation_scope_id: string
        }
        Update: {
          company_id?: string
          last_sequence?: number
          updated_at?: string
          valuation_scope_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "inventory_valuation_scope_sequences_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_valuation_scope_sequences_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "inventory_valuation_scope_sequences_valuation_scope_id_fkey"
            columns: ["valuation_scope_id"]
            isOneToOne: true
            referencedRelation: "inventory_valuation_scopes"
            referencedColumns: ["id"]
          },
        ]
      }
      inventory_valuation_scopes: {
        Row: {
          accounting_profile_id: string
          activation_state: string
          branch_id: string | null
          company_id: string
          cost_formula_policy_id: string
          created_at: string
          created_by: string
          effective_from: string
          effective_to: string | null
          id: string
          item_id: string
          scope_code: string
          scope_type: string
          valuation_currency_code: string
          warehouse_id: string | null
        }
        Insert: {
          accounting_profile_id: string
          activation_state?: string
          branch_id?: string | null
          company_id: string
          cost_formula_policy_id: string
          created_at?: string
          created_by: string
          effective_from: string
          effective_to?: string | null
          id?: string
          item_id: string
          scope_code: string
          scope_type: string
          valuation_currency_code: string
          warehouse_id?: string | null
        }
        Update: {
          accounting_profile_id?: string
          activation_state?: string
          branch_id?: string | null
          company_id?: string
          cost_formula_policy_id?: string
          created_at?: string
          created_by?: string
          effective_from?: string
          effective_to?: string | null
          id?: string
          item_id?: string
          scope_code?: string
          scope_type?: string
          valuation_currency_code?: string
          warehouse_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "inventory_valuation_scopes_accounting_profile_id_fkey"
            columns: ["accounting_profile_id"]
            isOneToOne: false
            referencedRelation: "inventory_accounting_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_valuation_scopes_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_valuation_scopes_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_valuation_scopes_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "inventory_valuation_scopes_cost_formula_policy_id_fkey"
            columns: ["cost_formula_policy_id"]
            isOneToOne: false
            referencedRelation: "inventory_cost_formula_policies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_valuation_scopes_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_valuation_scopes_warehouse_id_fkey"
            columns: ["warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
        ]
      }
      inventory_valuation_stream_sequences: {
        Row: {
          company_id: string
          last_sequence: number
          updated_at: string
          valuation_stream_id: string
        }
        Insert: {
          company_id: string
          last_sequence?: number
          updated_at?: string
          valuation_stream_id: string
        }
        Update: {
          company_id?: string
          last_sequence?: number
          updated_at?: string
          valuation_stream_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "inventory_valuation_stream_sequences_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_valuation_stream_sequences_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "inventory_valuation_stream_sequences_valuation_stream_id_fkey"
            columns: ["valuation_stream_id"]
            isOneToOne: true
            referencedRelation: "inventory_valuation_streams"
            referencedColumns: ["id"]
          },
        ]
      }
      inventory_valuation_streams: {
        Row: {
          activation_state: string
          company_id: string
          created_at: string
          created_by: string
          id: string
          item_id: string
          scope_code: string
        }
        Insert: {
          activation_state?: string
          company_id: string
          created_at?: string
          created_by: string
          id?: string
          item_id: string
          scope_code: string
        }
        Update: {
          activation_state?: string
          company_id?: string
          created_at?: string
          created_by?: string
          id?: string
          item_id?: string
          scope_code?: string
        }
        Relationships: [
          {
            foreignKeyName: "inventory_valuation_streams_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_valuation_streams_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "inventory_valuation_streams_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
        ]
      }
      item_barcodes: {
        Row: {
          barcode: string
          company_id: string
          created_at: string
          created_by: string | null
          id: string
          is_active: boolean
          is_primary: boolean
          item_id: string
          uom_id: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          barcode: string
          company_id: string
          created_at?: string
          created_by?: string | null
          id?: string
          is_active?: boolean
          is_primary?: boolean
          item_id: string
          uom_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          barcode?: string
          company_id?: string
          created_at?: string
          created_by?: string | null
          id?: string
          is_active?: boolean
          is_primary?: boolean
          item_id?: string
          uom_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "item_barcodes_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "item_barcodes_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "item_barcodes_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "item_barcodes_uom_id_fkey"
            columns: ["uom_id"]
            isOneToOne: false
            referencedRelation: "units_of_measure"
            referencedColumns: ["id"]
          },
        ]
      }
      item_categories: {
        Row: {
          adj_account_id: string | null
          category_code: string
          category_name: string
          cogs_account_id: string | null
          company_id: string
          created_at: string | null
          created_by: string | null
          description: string | null
          id: string
          inventory_account_id: string | null
          is_active: boolean | null
          parent_category_id: string | null
          sales_account_id: string | null
          updated_at: string | null
          updated_by: string | null
        }
        Insert: {
          adj_account_id?: string | null
          category_code: string
          category_name: string
          cogs_account_id?: string | null
          company_id: string
          created_at?: string | null
          created_by?: string | null
          description?: string | null
          id?: string
          inventory_account_id?: string | null
          is_active?: boolean | null
          parent_category_id?: string | null
          sales_account_id?: string | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Update: {
          adj_account_id?: string | null
          category_code?: string
          category_name?: string
          cogs_account_id?: string | null
          company_id?: string
          created_at?: string | null
          created_by?: string | null
          description?: string | null
          id?: string
          inventory_account_id?: string | null
          is_active?: boolean | null
          parent_category_id?: string | null
          sales_account_id?: string | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "item_categories_adj_account_id_fkey"
            columns: ["adj_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "item_categories_cogs_account_id_fkey"
            columns: ["cogs_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "item_categories_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "item_categories_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "item_categories_inventory_account_id_fkey"
            columns: ["inventory_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "item_categories_parent_category_id_fkey"
            columns: ["parent_category_id"]
            isOneToOne: false
            referencedRelation: "item_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "item_categories_sales_account_id_fkey"
            columns: ["sales_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      item_media: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          id: string
          is_active: boolean
          is_primary: boolean
          item_id: string
          media_type: string
          sort_order: number
          title: string | null
          updated_at: string
          updated_by: string | null
          url: string
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          id?: string
          is_active?: boolean
          is_primary?: boolean
          item_id: string
          media_type?: string
          sort_order?: number
          title?: string | null
          updated_at?: string
          updated_by?: string | null
          url: string
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          id?: string
          is_active?: boolean
          is_primary?: boolean
          item_id?: string
          media_type?: string
          sort_order?: number
          title?: string | null
          updated_at?: string
          updated_by?: string | null
          url?: string
        }
        Relationships: [
          {
            foreignKeyName: "item_media_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "item_media_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "item_media_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
        ]
      }
      item_uom_conversions: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          factor_to_base: number
          id: string
          is_active: boolean
          item_id: string
          uom_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          factor_to_base: number
          id?: string
          is_active?: boolean
          item_id: string
          uom_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          factor_to_base?: number
          id?: string
          is_active?: boolean
          item_id?: string
          uom_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "item_uom_conversions_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "item_uom_conversions_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "item_uom_conversions_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "item_uom_conversions_uom_id_fkey"
            columns: ["uom_id"]
            isOneToOne: false
            referencedRelation: "units_of_measure"
            referencedColumns: ["id"]
          },
        ]
      }
      items: {
        Row: {
          barcode: string | null
          category_id: string
          cogs_account_id: string | null
          company_id: string
          costing_method: string | null
          created_at: string | null
          created_by: string | null
          default_purchase_vat_id: string | null
          default_sales_vat_id: string | null
          description: string
          description_long: string | null
          id: string
          inventory_account_id: string | null
          is_active: boolean | null
          item_code: string
          item_type: string
          max_stock_level: number | null
          min_stock_level: number | null
          negative_stock_policy: string | null
          preferred_supplier_id: string | null
          price_is_vat_inclusive: boolean
          purchase_expense_account_id: string | null
          reorder_point: number | null
          reorder_quantity: number | null
          safety_stock: number | null
          sales_account_id: string | null
          specific_id_tracking: string | null
          standard_cost: number
          standard_selling_price: number
          track_batch: boolean
          track_serial: boolean
          uom_id: string
          updated_at: string | null
          updated_by: string | null
        }
        Insert: {
          barcode?: string | null
          category_id: string
          cogs_account_id?: string | null
          company_id: string
          costing_method?: string | null
          created_at?: string | null
          created_by?: string | null
          default_purchase_vat_id?: string | null
          default_sales_vat_id?: string | null
          description: string
          description_long?: string | null
          id?: string
          inventory_account_id?: string | null
          is_active?: boolean | null
          item_code: string
          item_type: string
          max_stock_level?: number | null
          min_stock_level?: number | null
          negative_stock_policy?: string | null
          preferred_supplier_id?: string | null
          price_is_vat_inclusive?: boolean
          purchase_expense_account_id?: string | null
          reorder_point?: number | null
          reorder_quantity?: number | null
          safety_stock?: number | null
          sales_account_id?: string | null
          specific_id_tracking?: string | null
          standard_cost?: number
          standard_selling_price?: number
          track_batch?: boolean
          track_serial?: boolean
          uom_id: string
          updated_at?: string | null
          updated_by?: string | null
        }
        Update: {
          barcode?: string | null
          category_id?: string
          cogs_account_id?: string | null
          company_id?: string
          costing_method?: string | null
          created_at?: string | null
          created_by?: string | null
          default_purchase_vat_id?: string | null
          default_sales_vat_id?: string | null
          description?: string
          description_long?: string | null
          id?: string
          inventory_account_id?: string | null
          is_active?: boolean | null
          item_code?: string
          item_type?: string
          max_stock_level?: number | null
          min_stock_level?: number | null
          negative_stock_policy?: string | null
          preferred_supplier_id?: string | null
          price_is_vat_inclusive?: boolean
          purchase_expense_account_id?: string | null
          reorder_point?: number | null
          reorder_quantity?: number | null
          safety_stock?: number | null
          sales_account_id?: string | null
          specific_id_tracking?: string | null
          standard_cost?: number
          standard_selling_price?: number
          track_batch?: boolean
          track_serial?: boolean
          uom_id?: string
          updated_at?: string | null
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "items_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "item_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "items_cogs_account_id_fkey"
            columns: ["cogs_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "items_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "items_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "items_default_purchase_vat_id_fkey"
            columns: ["default_purchase_vat_id"]
            isOneToOne: false
            referencedRelation: "vat_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "items_default_sales_vat_id_fkey"
            columns: ["default_sales_vat_id"]
            isOneToOne: false
            referencedRelation: "vat_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "items_inventory_account_id_fkey"
            columns: ["inventory_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "items_preferred_supplier_id_fkey"
            columns: ["preferred_supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "items_purchase_expense_account_id_fkey"
            columns: ["purchase_expense_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "items_sales_account_id_fkey"
            columns: ["sales_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "items_uom_id_fkey"
            columns: ["uom_id"]
            isOneToOne: false
            referencedRelation: "units_of_measure"
            referencedColumns: ["id"]
          },
        ]
      }
      itr_filings: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          filed_date: string | null
          form_type: string
          gross_income: number
          id: string
          period_quarter: number | null
          period_year: number
          reference_no: string | null
          remarks: string | null
          status: string
          tax_credits: number
          tax_due: number
          tax_payable: number
          taxable_income: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          filed_date?: string | null
          form_type: string
          gross_income?: number
          id?: string
          period_quarter?: number | null
          period_year: number
          reference_no?: string | null
          remarks?: string | null
          status?: string
          tax_credits?: number
          tax_due?: number
          tax_payable?: number
          taxable_income?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          filed_date?: string | null
          form_type?: string
          gross_income?: number
          id?: string
          period_quarter?: number | null
          period_year?: number
          reference_no?: string | null
          remarks?: string | null
          status?: string
          tax_credits?: number
          tax_due?: number
          tax_payable?: number
          taxable_income?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "itr_filings_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "itr_filings_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      journal_entries: {
        Row: {
          auto_reverse: boolean
          branch_id: string | null
          company_id: string
          created_at: string
          created_by: string | null
          description: string | null
          entry_class: string
          fiscal_period_id: string | null
          id: string
          is_auto_reversal: boolean
          je_date: string
          je_number: string
          posting_origin: string | null
          posting_run_id: string | null
          reference_doc_id: string | null
          reference_doc_type: string | null
          reversal_of_je_id: string | null
          reversed_by_je_id: string | null
          source_fingerprint: string | null
          status: string
          total_credit: number
          total_debit: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          auto_reverse?: boolean
          branch_id?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          entry_class?: string
          fiscal_period_id?: string | null
          id?: string
          is_auto_reversal?: boolean
          je_date: string
          je_number: string
          posting_origin?: string | null
          posting_run_id?: string | null
          reference_doc_id?: string | null
          reference_doc_type?: string | null
          reversal_of_je_id?: string | null
          reversed_by_je_id?: string | null
          source_fingerprint?: string | null
          status?: string
          total_credit?: number
          total_debit?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          auto_reverse?: boolean
          branch_id?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          entry_class?: string
          fiscal_period_id?: string | null
          id?: string
          is_auto_reversal?: boolean
          je_date?: string
          je_number?: string
          posting_origin?: string | null
          posting_run_id?: string | null
          reference_doc_id?: string | null
          reference_doc_type?: string | null
          reversal_of_je_id?: string | null
          reversed_by_je_id?: string | null
          source_fingerprint?: string | null
          status?: string
          total_credit?: number
          total_debit?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "journal_entries_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entries_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entries_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "journal_entries_fiscal_period_id_fkey"
            columns: ["fiscal_period_id"]
            isOneToOne: false
            referencedRelation: "fiscal_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entries_reference_doc_type_fkey"
            columns: ["reference_doc_type"]
            isOneToOne: false
            referencedRelation: "ref_posting_source_types"
            referencedColumns: ["document_type"]
          },
          {
            foreignKeyName: "journal_entries_reversal_of_je_id_fkey"
            columns: ["reversal_of_je_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entries_reversed_by_je_id_fkey"
            columns: ["reversed_by_je_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
        ]
      }
      journal_entry_lines: {
        Row: {
          account_id: string
          branch_id: string | null
          company_id: string
          cost_center_id: string | null
          created_at: string
          created_by: string | null
          credit_amount: number
          debit_amount: number
          department_id: string | null
          description: string | null
          functional_entity_id: string | null
          id: string
          je_id: string
          line_number: number
          line_role: string | null
          location_id: string | null
          project_id: string | null
          source_line_id: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          account_id: string
          branch_id?: string | null
          company_id: string
          cost_center_id?: string | null
          created_at?: string
          created_by?: string | null
          credit_amount?: number
          debit_amount?: number
          department_id?: string | null
          description?: string | null
          functional_entity_id?: string | null
          id?: string
          je_id: string
          line_number: number
          line_role?: string | null
          location_id?: string | null
          project_id?: string | null
          source_line_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          account_id?: string
          branch_id?: string | null
          company_id?: string
          cost_center_id?: string | null
          created_at?: string
          created_by?: string | null
          credit_amount?: number
          debit_amount?: number
          department_id?: string | null
          description?: string | null
          functional_entity_id?: string | null
          id?: string
          je_id?: string
          line_number?: number
          line_role?: string | null
          location_id?: string | null
          project_id?: string | null
          source_line_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "journal_entry_lines_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entry_lines_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entry_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entry_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "journal_entry_lines_cost_center_id_fkey"
            columns: ["cost_center_id"]
            isOneToOne: false
            referencedRelation: "cost_centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entry_lines_department_id_fkey"
            columns: ["department_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entry_lines_functional_entity_id_fkey"
            columns: ["functional_entity_id"]
            isOneToOne: false
            referencedRelation: "functional_entities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entry_lines_je_id_fkey"
            columns: ["je_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entry_lines_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entry_lines_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
        ]
      }
      locations: {
        Row: {
          branch_id: string | null
          company_id: string
          created_at: string
          created_by: string | null
          description: string | null
          id: string
          is_active: boolean
          location_code: string
          location_name: string
          location_type: string
          parent_location_id: string | null
          updated_at: string
          updated_by: string | null
          valid_from: string | null
          valid_to: string | null
        }
        Insert: {
          branch_id?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          is_active?: boolean
          location_code: string
          location_name: string
          location_type?: string
          parent_location_id?: string | null
          updated_at?: string
          updated_by?: string | null
          valid_from?: string | null
          valid_to?: string | null
        }
        Update: {
          branch_id?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          is_active?: boolean
          location_code?: string
          location_name?: string
          location_type?: string
          parent_location_id?: string | null
          updated_at?: string
          updated_by?: string | null
          valid_from?: string | null
          valid_to?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "locations_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "locations_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "locations_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "locations_parent_location_id_fkey"
            columns: ["parent_location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
        ]
      }
      master_data_export_logs: {
        Row: {
          company_id: string | null
          content_hash: string
          export_format: string
          exported_at: string
          exported_by: string | null
          id: string
          master_key: string
          row_count: number
        }
        Insert: {
          company_id?: string | null
          content_hash: string
          export_format?: string
          exported_at?: string
          exported_by?: string | null
          id?: string
          master_key: string
          row_count?: number
        }
        Update: {
          company_id?: string | null
          content_hash?: string
          export_format?: string
          exported_at?: string
          exported_by?: string | null
          id?: string
          master_key?: string
          row_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "master_data_export_logs_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "master_data_export_logs_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "master_data_export_logs_master_key_fkey"
            columns: ["master_key"]
            isOneToOne: false
            referencedRelation: "master_data_import_registry"
            referencedColumns: ["master_key"]
          },
        ]
      }
      master_data_import_batches: {
        Row: {
          company_id: string | null
          completed_at: string | null
          created_at: string
          created_by: string | null
          error_count: number
          error_summary: Json
          id: string
          idempotency_key: string | null
          input_hash: string
          inserted_count: number
          master_key: string
          mode: string
          options: Json
          row_count: number
          skipped_count: number
          status: string
          updated_count: number
          valid_row_count: number
        }
        Insert: {
          company_id?: string | null
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          error_count?: number
          error_summary?: Json
          id?: string
          idempotency_key?: string | null
          input_hash: string
          inserted_count?: number
          master_key: string
          mode: string
          options?: Json
          row_count?: number
          skipped_count?: number
          status: string
          updated_count?: number
          valid_row_count?: number
        }
        Update: {
          company_id?: string | null
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          error_count?: number
          error_summary?: Json
          id?: string
          idempotency_key?: string | null
          input_hash?: string
          inserted_count?: number
          master_key?: string
          mode?: string
          options?: Json
          row_count?: number
          skipped_count?: number
          status?: string
          updated_count?: number
          valid_row_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "master_data_import_batches_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "master_data_import_batches_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "master_data_import_batches_master_key_fkey"
            columns: ["master_key"]
            isOneToOne: false
            referencedRelation: "master_data_import_registry"
            referencedColumns: ["master_key"]
          },
        ]
      }
      master_data_import_registry: {
        Row: {
          business_key_columns: string[]
          created_at: string
          display_name: string
          export_sequence: number
          import_mode: string
          master_key: string
          notes: string | null
          scope: string
          sort_columns: string[]
          table_name: string
          table_schema: string
          updated_at: string
        }
        Insert: {
          business_key_columns?: string[]
          created_at?: string
          display_name: string
          export_sequence: number
          import_mode?: string
          master_key: string
          notes?: string | null
          scope: string
          sort_columns?: string[]
          table_name: string
          table_schema?: string
          updated_at?: string
        }
        Update: {
          business_key_columns?: string[]
          created_at?: string
          display_name?: string
          export_sequence?: number
          import_mode?: string
          master_key?: string
          notes?: string | null
          scope?: string
          sort_columns?: string[]
          table_name?: string
          table_schema?: string
          updated_at?: string
        }
        Relationships: []
      }
      master_data_import_rows: {
        Row: {
          action: string
          batch_id: string
          created_at: string
          id: string
          imported_at: string | null
          is_valid: boolean
          record_id: string | null
          row_number: number
          source_row: Json
          validation_errors: Json
        }
        Insert: {
          action: string
          batch_id: string
          created_at?: string
          id?: string
          imported_at?: string | null
          is_valid?: boolean
          record_id?: string | null
          row_number: number
          source_row: Json
          validation_errors?: Json
        }
        Update: {
          action?: string
          batch_id?: string
          created_at?: string
          id?: string
          imported_at?: string | null
          is_valid?: boolean
          record_id?: string | null
          row_number?: number
          source_row?: Json
          validation_errors?: Json
        }
        Relationships: [
          {
            foreignKeyName: "master_data_import_rows_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "master_data_import_batches"
            referencedColumns: ["id"]
          },
        ]
      }
      master_data_permissions: {
        Row: {
          action: string
          created_at: string
          id: string
          is_available: boolean
          is_sensitive: boolean
          master_key: string
          notes: string | null
          permission_code: string
          updated_at: string
        }
        Insert: {
          action: string
          created_at?: string
          id?: string
          is_available?: boolean
          is_sensitive?: boolean
          master_key: string
          notes?: string | null
          permission_code: string
          updated_at?: string
        }
        Update: {
          action?: string
          created_at?: string
          id?: string
          is_available?: boolean
          is_sensitive?: boolean
          master_key?: string
          notes?: string | null
          permission_code?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "master_data_permissions_master_key_fkey"
            columns: ["master_key"]
            isOneToOne: false
            referencedRelation: "master_data_import_registry"
            referencedColumns: ["master_key"]
          },
        ]
      }
      master_data_role_permissions: {
        Row: {
          granted_at: string
          granted_by: string | null
          id: string
          is_allowed: boolean
          permission_code: string
          role_code: string
          updated_at: string
        }
        Insert: {
          granted_at?: string
          granted_by?: string | null
          id?: string
          is_allowed?: boolean
          permission_code: string
          role_code: string
          updated_at?: string
        }
        Update: {
          granted_at?: string
          granted_by?: string | null
          id?: string
          is_allowed?: boolean
          permission_code?: string
          role_code?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "master_data_role_permissions_permission_code_fkey"
            columns: ["permission_code"]
            isOneToOne: false
            referencedRelation: "master_data_permissions"
            referencedColumns: ["permission_code"]
          },
        ]
      }
      master_data_sod_conflicts: {
        Row: {
          conflict_code: string
          created_at: string
          enforcement_mode: string
          id: string
          is_active: boolean
          left_permission_code: string
          notes: string | null
          right_permission_code: string
          severity: string
          updated_at: string
        }
        Insert: {
          conflict_code: string
          created_at?: string
          enforcement_mode?: string
          id?: string
          is_active?: boolean
          left_permission_code: string
          notes?: string | null
          right_permission_code: string
          severity?: string
          updated_at?: string
        }
        Update: {
          conflict_code?: string
          created_at?: string
          enforcement_mode?: string
          id?: string
          is_active?: boolean
          left_permission_code?: string
          notes?: string | null
          right_permission_code?: string
          severity?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "master_data_sod_conflicts_left_permission_code_fkey"
            columns: ["left_permission_code"]
            isOneToOne: false
            referencedRelation: "master_data_permissions"
            referencedColumns: ["permission_code"]
          },
          {
            foreignKeyName: "master_data_sod_conflicts_right_permission_code_fkey"
            columns: ["right_permission_code"]
            isOneToOne: false
            referencedRelation: "master_data_permissions"
            referencedColumns: ["permission_code"]
          },
        ]
      }
      mcit_computations: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          excess_mcit_carryforward: number
          gross_income: number
          id: string
          mcit_due: number
          mcit_rate: number
          period_year: number
          rcit_due: number
          remarks: string | null
          status: string
          tax_due_higher: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          excess_mcit_carryforward?: number
          gross_income?: number
          id?: string
          mcit_due?: number
          mcit_rate?: number
          period_year: number
          rcit_due?: number
          remarks?: string | null
          status?: string
          tax_due_higher?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          excess_mcit_carryforward?: number
          gross_income?: number
          id?: string
          mcit_due?: number
          mcit_rate?: number
          period_year?: number
          rcit_due?: number
          remarks?: string | null
          status?: string
          tax_due_higher?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "mcit_computations_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "mcit_computations_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      nolco_schedule: {
        Row: {
          applied_year1: number
          applied_year2: number
          applied_year3: number
          company_id: string
          created_at: string
          created_by: string | null
          expiry_year: number
          id: string
          nolco_amount: number
          remarks: string | null
          updated_at: string
          updated_by: string | null
          year_incurred: number
        }
        Insert: {
          applied_year1?: number
          applied_year2?: number
          applied_year3?: number
          company_id: string
          created_at?: string
          created_by?: string | null
          expiry_year: number
          id?: string
          nolco_amount?: number
          remarks?: string | null
          updated_at?: string
          updated_by?: string | null
          year_incurred: number
        }
        Update: {
          applied_year1?: number
          applied_year2?: number
          applied_year3?: number
          company_id?: string
          created_at?: string
          created_by?: string | null
          expiry_year?: number
          id?: string
          nolco_amount?: number
          remarks?: string | null
          updated_at?: string
          updated_by?: string | null
          year_incurred?: number
        }
        Relationships: [
          {
            foreignKeyName: "nolco_schedule_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "nolco_schedule_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      number_series: {
        Row: {
          allow_manual_override: boolean | null
          atp_alert_threshold: number | null
          atp_series_end: number | null
          atp_series_start: number | null
          branch_id: string
          company_id: string
          created_at: string | null
          created_by: string | null
          current_sequence: number | null
          document_code: string | null
          document_type_id: string
          has_dynamic_year: boolean | null
          id: string
          is_active: boolean | null
          last_reset_date: string | null
          next_number: number
          number_length: number
          padding: number | null
          prefix: string | null
          reset_frequency: string
          starting_number: number
          suffix: string | null
          updated_at: string | null
          updated_by: string | null
        }
        Insert: {
          allow_manual_override?: boolean | null
          atp_alert_threshold?: number | null
          atp_series_end?: number | null
          atp_series_start?: number | null
          branch_id: string
          company_id: string
          created_at?: string | null
          created_by?: string | null
          current_sequence?: number | null
          document_code?: string | null
          document_type_id: string
          has_dynamic_year?: boolean | null
          id?: string
          is_active?: boolean | null
          last_reset_date?: string | null
          next_number?: number
          number_length?: number
          padding?: number | null
          prefix?: string | null
          reset_frequency?: string
          starting_number?: number
          suffix?: string | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Update: {
          allow_manual_override?: boolean | null
          atp_alert_threshold?: number | null
          atp_series_end?: number | null
          atp_series_start?: number | null
          branch_id?: string
          company_id?: string
          created_at?: string | null
          created_by?: string | null
          current_sequence?: number | null
          document_code?: string | null
          document_type_id?: string
          has_dynamic_year?: boolean | null
          id?: string
          is_active?: boolean | null
          last_reset_date?: string | null
          next_number?: number
          number_length?: number
          padding?: number | null
          prefix?: string | null
          reset_frequency?: string
          starting_number?: number
          suffix?: string | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "number_series_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "number_series_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "number_series_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "number_series_document_type_id_fkey"
            columns: ["document_type_id"]
            isOneToOne: false
            referencedRelation: "ref_document_types"
            referencedColumns: ["id"]
          },
        ]
      }
      opening_balance_ap_lines: {
        Row: {
          batch_id: string
          bill_date: string
          company_id: string
          created_at: string
          created_by: string | null
          due_date: string | null
          id: string
          legacy_bill_number: string
          line_number: number
          memo: string | null
          original_amount: number
          supplier_id: string
          supplier_invoice_number: string | null
        }
        Insert: {
          batch_id: string
          bill_date: string
          company_id: string
          created_at?: string
          created_by?: string | null
          due_date?: string | null
          id?: string
          legacy_bill_number: string
          line_number: number
          memo?: string | null
          original_amount: number
          supplier_id: string
          supplier_invoice_number?: string | null
        }
        Update: {
          batch_id?: string
          bill_date?: string
          company_id?: string
          created_at?: string
          created_by?: string | null
          due_date?: string | null
          id?: string
          legacy_bill_number?: string
          line_number?: number
          memo?: string | null
          original_amount?: number
          supplier_id?: string
          supplier_invoice_number?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "opening_balance_ap_lines_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "opening_balance_batches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opening_balance_ap_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opening_balance_ap_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "opening_balance_ap_lines_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
      opening_balance_ar_lines: {
        Row: {
          batch_id: string
          company_id: string
          created_at: string
          created_by: string | null
          customer_id: string
          due_date: string | null
          id: string
          invoice_date: string
          legacy_invoice_number: string
          line_number: number
          memo: string | null
          original_amount: number
        }
        Insert: {
          batch_id: string
          company_id: string
          created_at?: string
          created_by?: string | null
          customer_id: string
          due_date?: string | null
          id?: string
          invoice_date: string
          legacy_invoice_number: string
          line_number: number
          memo?: string | null
          original_amount: number
        }
        Update: {
          batch_id?: string
          company_id?: string
          created_at?: string
          created_by?: string | null
          customer_id?: string
          due_date?: string | null
          id?: string
          invoice_date?: string
          legacy_invoice_number?: string
          line_number?: number
          memo?: string | null
          original_amount?: number
        }
        Relationships: [
          {
            foreignKeyName: "opening_balance_ar_lines_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "opening_balance_batches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opening_balance_ar_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opening_balance_ar_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "opening_balance_ar_lines_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
        ]
      }
      opening_balance_bank_lines: {
        Row: {
          amount: number
          bank_account_id: string
          batch_id: string
          company_id: string
          created_at: string
          created_by: string | null
          id: string
          line_number: number
          memo: string | null
        }
        Insert: {
          amount: number
          bank_account_id: string
          batch_id: string
          company_id: string
          created_at?: string
          created_by?: string | null
          id?: string
          line_number: number
          memo?: string | null
        }
        Update: {
          amount?: number
          bank_account_id?: string
          batch_id?: string
          company_id?: string
          created_at?: string
          created_by?: string | null
          id?: string
          line_number?: number
          memo?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "opening_balance_bank_lines_bank_account_id_fkey"
            columns: ["bank_account_id"]
            isOneToOne: false
            referencedRelation: "bank_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opening_balance_bank_lines_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "opening_balance_batches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opening_balance_bank_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opening_balance_bank_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      opening_balance_batches: {
        Row: {
          batch_number: string
          branch_id: string | null
          company_id: string
          created_at: string
          created_by: string | null
          currency_code: string
          cutover_date: string
          description: string | null
          id: string
          journal_entry_id: string | null
          posted_at: string | null
          posted_by: string | null
          reversal_je_id: string | null
          reversal_reason: string | null
          reversed_at: string | null
          reversed_by: string | null
          status: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          batch_number: string
          branch_id?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          currency_code?: string
          cutover_date: string
          description?: string | null
          id?: string
          journal_entry_id?: string | null
          posted_at?: string | null
          posted_by?: string | null
          reversal_je_id?: string | null
          reversal_reason?: string | null
          reversed_at?: string | null
          reversed_by?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          batch_number?: string
          branch_id?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          currency_code?: string
          cutover_date?: string
          description?: string | null
          id?: string
          journal_entry_id?: string | null
          posted_at?: string | null
          posted_by?: string | null
          reversal_je_id?: string | null
          reversal_reason?: string | null
          reversed_at?: string | null
          reversed_by?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "opening_balance_batches_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opening_balance_batches_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opening_balance_batches_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "opening_balance_batches_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opening_balance_batches_reversal_je_id_fkey"
            columns: ["reversal_je_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
        ]
      }
      opening_balance_gl_lines: {
        Row: {
          account_id: string
          batch_id: string
          company_id: string
          created_at: string
          created_by: string | null
          credit_amount: number
          debit_amount: number
          description: string | null
          id: string
          line_number: number
        }
        Insert: {
          account_id: string
          batch_id: string
          company_id: string
          created_at?: string
          created_by?: string | null
          credit_amount?: number
          debit_amount?: number
          description?: string | null
          id?: string
          line_number: number
        }
        Update: {
          account_id?: string
          batch_id?: string
          company_id?: string
          created_at?: string
          created_by?: string | null
          credit_amount?: number
          debit_amount?: number
          description?: string | null
          id?: string
          line_number?: number
        }
        Relationships: [
          {
            foreignKeyName: "opening_balance_gl_lines_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opening_balance_gl_lines_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "opening_balance_batches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opening_balance_gl_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opening_balance_gl_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      opening_balance_inventory_lines: {
        Row: {
          batch_id: string
          company_id: string
          created_at: string
          created_by: string | null
          id: string
          item_id: string
          line_number: number
          lot_number: string | null
          memo: string | null
          quantity: number
          serial_number: string | null
          total_cost: number | null
          unit_cost: number
          warehouse_id: string
        }
        Insert: {
          batch_id: string
          company_id: string
          created_at?: string
          created_by?: string | null
          id?: string
          item_id: string
          line_number: number
          lot_number?: string | null
          memo?: string | null
          quantity: number
          serial_number?: string | null
          total_cost?: number | null
          unit_cost: number
          warehouse_id: string
        }
        Update: {
          batch_id?: string
          company_id?: string
          created_at?: string
          created_by?: string | null
          id?: string
          item_id?: string
          line_number?: number
          lot_number?: string | null
          memo?: string | null
          quantity?: number
          serial_number?: string | null
          total_cost?: number | null
          unit_cost?: number
          warehouse_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "opening_balance_inventory_lines_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "opening_balance_batches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opening_balance_inventory_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opening_balance_inventory_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "opening_balance_inventory_lines_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opening_balance_inventory_lines_warehouse_id_fkey"
            columns: ["warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
        ]
      }
      party_contacts: {
        Row: {
          company_id: string
          contact_name: string
          created_at: string
          created_by: string | null
          customer_id: string | null
          description: string | null
          email: string | null
          id: string
          is_active: boolean
          is_primary: boolean
          mobile_number: string | null
          phone_number: string | null
          position: string | null
          supplier_id: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          company_id: string
          contact_name: string
          created_at?: string
          created_by?: string | null
          customer_id?: string | null
          description?: string | null
          email?: string | null
          id?: string
          is_active?: boolean
          is_primary?: boolean
          mobile_number?: string | null
          phone_number?: string | null
          position?: string | null
          supplier_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          company_id?: string
          contact_name?: string
          created_at?: string
          created_by?: string | null
          customer_id?: string | null
          description?: string | null
          email?: string | null
          id?: string
          is_active?: boolean
          is_primary?: boolean
          mobile_number?: string | null
          phone_number?: string | null
          position?: string | null
          supplier_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "party_contacts_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "party_contacts_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "party_contacts_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "party_contacts_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
      payment_terms: {
        Row: {
          company_id: string
          created_at: string | null
          created_by: string | null
          days_to_due: number
          dp_percentage: number | null
          id: string
          is_active: boolean | null
          require_downpayment: boolean
          term_code: string
          term_name: string
          updated_at: string | null
          updated_by: string | null
        }
        Insert: {
          company_id: string
          created_at?: string | null
          created_by?: string | null
          days_to_due?: number
          dp_percentage?: number | null
          id?: string
          is_active?: boolean | null
          require_downpayment?: boolean
          term_code: string
          term_name: string
          updated_at?: string | null
          updated_by?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string | null
          created_by?: string | null
          days_to_due?: number
          dp_percentage?: number | null
          id?: string
          is_active?: boolean | null
          require_downpayment?: boolean
          term_code?: string
          term_name?: string
          updated_at?: string | null
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "payment_terms_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_terms_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      payment_voucher_lines: {
        Row: {
          atc_code_id: string | null
          company_id: string
          created_at: string
          created_by: string | null
          ewt_amount: number
          ewt_income_nature: string | null
          ewt_tax_base: number | null
          ewt_variance_reason: string | null
          id: string
          line_type: string
          opening_ap_line_id: string | null
          payment_amount: number
          payment_voucher_id: string
          updated_at: string
          updated_by: string | null
          vendor_bill_id: string | null
        }
        Insert: {
          atc_code_id?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          ewt_amount?: number
          ewt_income_nature?: string | null
          ewt_tax_base?: number | null
          ewt_variance_reason?: string | null
          id?: string
          line_type?: string
          opening_ap_line_id?: string | null
          payment_amount?: number
          payment_voucher_id: string
          updated_at?: string
          updated_by?: string | null
          vendor_bill_id?: string | null
        }
        Update: {
          atc_code_id?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          ewt_amount?: number
          ewt_income_nature?: string | null
          ewt_tax_base?: number | null
          ewt_variance_reason?: string | null
          id?: string
          line_type?: string
          opening_ap_line_id?: string | null
          payment_amount?: number
          payment_voucher_id?: string
          updated_at?: string
          updated_by?: string | null
          vendor_bill_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "payment_voucher_lines_atc_code_id_fkey"
            columns: ["atc_code_id"]
            isOneToOne: false
            referencedRelation: "atc_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_voucher_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_voucher_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "payment_voucher_lines_opening_ap_line_id_fkey"
            columns: ["opening_ap_line_id"]
            isOneToOne: false
            referencedRelation: "opening_balance_ap_lines"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_voucher_lines_payment_voucher_id_fkey"
            columns: ["payment_voucher_id"]
            isOneToOne: false
            referencedRelation: "payment_vouchers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_voucher_lines_payment_voucher_id_fkey"
            columns: ["payment_voucher_id"]
            isOneToOne: false
            referencedRelation: "vw_payment_register"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_voucher_lines_vendor_bill_id_fkey"
            columns: ["vendor_bill_id"]
            isOneToOne: false
            referencedRelation: "vendor_bills"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_voucher_lines_vendor_bill_id_fkey"
            columns: ["vendor_bill_id"]
            isOneToOne: false
            referencedRelation: "vw_ap_aging"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_voucher_lines_vendor_bill_id_fkey"
            columns: ["vendor_bill_id"]
            isOneToOne: false
            referencedRelation: "vw_vendor_bill_register"
            referencedColumns: ["id"]
          },
        ]
      }
      payment_vouchers: {
        Row: {
          bank_account_id: string | null
          branch_id: string | null
          check_date: string | null
          check_number: string | null
          cleared_by: string | null
          company_id: string
          created_at: string
          created_by: string | null
          date_cleared: string | null
          date_released: string | null
          id: string
          journal_entry_id: string | null
          payee_account_name_snapshot: string | null
          payee_account_number_snapshot: string | null
          payee_bank_branch_snapshot: string | null
          payee_bank_name_snapshot: string | null
          payee_swift_snapshot: string | null
          payment_mode_id: string | null
          posted_at: string | null
          posted_by: string | null
          reference_number: string | null
          released_by: string | null
          remarks: string | null
          status: string
          supplier_bank_account_id: string | null
          supplier_id: string
          supplier_name_snapshot: string
          supplier_tin_snapshot: string | null
          total_amount: number
          total_ewt: number
          updated_at: string
          updated_by: string | null
          voucher_date: string
          voucher_number: string
        }
        Insert: {
          bank_account_id?: string | null
          branch_id?: string | null
          check_date?: string | null
          check_number?: string | null
          cleared_by?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          date_cleared?: string | null
          date_released?: string | null
          id?: string
          journal_entry_id?: string | null
          payee_account_name_snapshot?: string | null
          payee_account_number_snapshot?: string | null
          payee_bank_branch_snapshot?: string | null
          payee_bank_name_snapshot?: string | null
          payee_swift_snapshot?: string | null
          payment_mode_id?: string | null
          posted_at?: string | null
          posted_by?: string | null
          reference_number?: string | null
          released_by?: string | null
          remarks?: string | null
          status?: string
          supplier_bank_account_id?: string | null
          supplier_id: string
          supplier_name_snapshot: string
          supplier_tin_snapshot?: string | null
          total_amount?: number
          total_ewt?: number
          updated_at?: string
          updated_by?: string | null
          voucher_date: string
          voucher_number: string
        }
        Update: {
          bank_account_id?: string | null
          branch_id?: string | null
          check_date?: string | null
          check_number?: string | null
          cleared_by?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          date_cleared?: string | null
          date_released?: string | null
          id?: string
          journal_entry_id?: string | null
          payee_account_name_snapshot?: string | null
          payee_account_number_snapshot?: string | null
          payee_bank_branch_snapshot?: string | null
          payee_bank_name_snapshot?: string | null
          payee_swift_snapshot?: string | null
          payment_mode_id?: string | null
          posted_at?: string | null
          posted_by?: string | null
          reference_number?: string | null
          released_by?: string | null
          remarks?: string | null
          status?: string
          supplier_bank_account_id?: string | null
          supplier_id?: string
          supplier_name_snapshot?: string
          supplier_tin_snapshot?: string | null
          total_amount?: number
          total_ewt?: number
          updated_at?: string
          updated_by?: string | null
          voucher_date?: string
          voucher_number?: string
        }
        Relationships: [
          {
            foreignKeyName: "payment_vouchers_bank_account_id_fkey"
            columns: ["bank_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_vouchers_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_vouchers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_vouchers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "payment_vouchers_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_vouchers_payment_mode_id_fkey"
            columns: ["payment_mode_id"]
            isOneToOne: false
            referencedRelation: "ref_payment_modes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_vouchers_supplier_bank_account_id_fkey"
            columns: ["supplier_bank_account_id"]
            isOneToOne: false
            referencedRelation: "supplier_bank_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_vouchers_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
      percentage_tax_codes: {
        Row: {
          atc_id: string
          company_id: string
          created_at: string | null
          created_by: string | null
          deprecated_at: string | null
          deprecated_reason: string | null
          description: string
          effective_from: string
          effective_to: string | null
          form_type: string
          id: string
          is_active: boolean | null
          pt_code: string
          rate: number
          supersedes_percentage_tax_code_id: string | null
          tax_code_id: string
          updated_at: string | null
          updated_by: string | null
        }
        Insert: {
          atc_id: string
          company_id: string
          created_at?: string | null
          created_by?: string | null
          deprecated_at?: string | null
          deprecated_reason?: string | null
          description: string
          effective_from?: string
          effective_to?: string | null
          form_type?: string
          id?: string
          is_active?: boolean | null
          pt_code: string
          rate: number
          supersedes_percentage_tax_code_id?: string | null
          tax_code_id: string
          updated_at?: string | null
          updated_by?: string | null
        }
        Update: {
          atc_id?: string
          company_id?: string
          created_at?: string | null
          created_by?: string | null
          deprecated_at?: string | null
          deprecated_reason?: string | null
          description?: string
          effective_from?: string
          effective_to?: string | null
          form_type?: string
          id?: string
          is_active?: boolean | null
          pt_code?: string
          rate?: number
          supersedes_percentage_tax_code_id?: string | null
          tax_code_id?: string
          updated_at?: string | null
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "percentage_tax_codes_atc_id_fkey"
            columns: ["atc_id"]
            isOneToOne: false
            referencedRelation: "atc_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "percentage_tax_codes_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "percentage_tax_codes_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "percentage_tax_codes_supersedes_percentage_tax_code_id_fkey"
            columns: ["supersedes_percentage_tax_code_id"]
            isOneToOne: false
            referencedRelation: "percentage_tax_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "percentage_tax_codes_tax_code_id_fkey"
            columns: ["tax_code_id"]
            isOneToOne: false
            referencedRelation: "tax_codes"
            referencedColumns: ["id"]
          },
        ]
      }
      petty_cash_funds: {
        Row: {
          authorized_amount: number
          branch_id: string | null
          company_id: string
          created_at: string
          created_by: string | null
          custodian_name: string
          fund_name: string
          gl_account_id: string
          id: string
          is_active: boolean
          replenishment_threshold: number | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          authorized_amount: number
          branch_id?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          custodian_name: string
          fund_name: string
          gl_account_id: string
          id?: string
          is_active?: boolean
          replenishment_threshold?: number | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          authorized_amount?: number
          branch_id?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          custodian_name?: string
          fund_name?: string
          gl_account_id?: string
          id?: string
          is_active?: boolean
          replenishment_threshold?: number | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "petty_cash_funds_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "petty_cash_funds_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "petty_cash_funds_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "petty_cash_funds_gl_account_id_fkey"
            columns: ["gl_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      petty_cash_replenishments: {
        Row: {
          bank_account_id: string | null
          branch_id: string | null
          check_number: string | null
          company_id: string
          created_at: string
          created_by: string | null
          fiscal_period_id: string | null
          fund_id: string
          id: string
          journal_entry_id: string | null
          pcr_number: string
          posted_at: string | null
          posted_by: string | null
          remarks: string | null
          replenishment_date: string
          status: string
          total_amount: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          bank_account_id?: string | null
          branch_id?: string | null
          check_number?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          fiscal_period_id?: string | null
          fund_id: string
          id?: string
          journal_entry_id?: string | null
          pcr_number: string
          posted_at?: string | null
          posted_by?: string | null
          remarks?: string | null
          replenishment_date: string
          status?: string
          total_amount?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          bank_account_id?: string | null
          branch_id?: string | null
          check_number?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          fiscal_period_id?: string | null
          fund_id?: string
          id?: string
          journal_entry_id?: string | null
          pcr_number?: string
          posted_at?: string | null
          posted_by?: string | null
          remarks?: string | null
          replenishment_date?: string
          status?: string
          total_amount?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "petty_cash_replenishments_bank_account_id_fkey"
            columns: ["bank_account_id"]
            isOneToOne: false
            referencedRelation: "bank_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "petty_cash_replenishments_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "petty_cash_replenishments_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "petty_cash_replenishments_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "petty_cash_replenishments_fiscal_period_id_fkey"
            columns: ["fiscal_period_id"]
            isOneToOne: false
            referencedRelation: "fiscal_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "petty_cash_replenishments_fund_id_fkey"
            columns: ["fund_id"]
            isOneToOne: false
            referencedRelation: "petty_cash_funds"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "petty_cash_replenishments_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
        ]
      }
      petty_cash_vouchers: {
        Row: {
          amount: number
          branch_id: string | null
          company_id: string
          created_at: string
          created_by: string | null
          expense_account_id: string
          fiscal_period_id: string | null
          fund_id: string
          id: string
          journal_entry_id: string | null
          payee: string
          pcv_number: string
          posted_at: string | null
          posted_by: string | null
          purpose: string
          receipt_number: string | null
          replenishment_id: string | null
          status: string
          updated_at: string
          updated_by: string | null
          voucher_date: string
        }
        Insert: {
          amount: number
          branch_id?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          expense_account_id: string
          fiscal_period_id?: string | null
          fund_id: string
          id?: string
          journal_entry_id?: string | null
          payee: string
          pcv_number: string
          posted_at?: string | null
          posted_by?: string | null
          purpose: string
          receipt_number?: string | null
          replenishment_id?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
          voucher_date: string
        }
        Update: {
          amount?: number
          branch_id?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          expense_account_id?: string
          fiscal_period_id?: string | null
          fund_id?: string
          id?: string
          journal_entry_id?: string | null
          payee?: string
          pcv_number?: string
          posted_at?: string | null
          posted_by?: string | null
          purpose?: string
          receipt_number?: string | null
          replenishment_id?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
          voucher_date?: string
        }
        Relationships: [
          {
            foreignKeyName: "petty_cash_vouchers_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "petty_cash_vouchers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "petty_cash_vouchers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "petty_cash_vouchers_expense_account_id_fkey"
            columns: ["expense_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "petty_cash_vouchers_fiscal_period_id_fkey"
            columns: ["fiscal_period_id"]
            isOneToOne: false
            referencedRelation: "fiscal_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "petty_cash_vouchers_fund_id_fkey"
            columns: ["fund_id"]
            isOneToOne: false
            referencedRelation: "petty_cash_funds"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "petty_cash_vouchers_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "petty_cash_vouchers_replenishment_id_fkey"
            columns: ["replenishment_id"]
            isOneToOne: false
            referencedRelation: "petty_cash_replenishments"
            referencedColumns: ["id"]
          },
        ]
      }
      physical_count_sheet_lines: {
        Row: {
          company_id: string
          count_sheet_id: string
          counted_qty: number | null
          gl_variance_account_id: string | null
          id: string
          inventory_cost_layer_id: string | null
          inventory_transaction_id: string | null
          item_id: string
          lot_number: string | null
          serial_number: string | null
          system_qty: number
          unit_cost: number
        }
        Insert: {
          company_id: string
          count_sheet_id: string
          counted_qty?: number | null
          gl_variance_account_id?: string | null
          id?: string
          inventory_cost_layer_id?: string | null
          inventory_transaction_id?: string | null
          item_id: string
          lot_number?: string | null
          serial_number?: string | null
          system_qty?: number
          unit_cost?: number
        }
        Update: {
          company_id?: string
          count_sheet_id?: string
          counted_qty?: number | null
          gl_variance_account_id?: string | null
          id?: string
          inventory_cost_layer_id?: string | null
          inventory_transaction_id?: string | null
          item_id?: string
          lot_number?: string | null
          serial_number?: string | null
          system_qty?: number
          unit_cost?: number
        }
        Relationships: [
          {
            foreignKeyName: "physical_count_sheet_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "physical_count_sheet_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "physical_count_sheet_lines_count_sheet_id_fkey"
            columns: ["count_sheet_id"]
            isOneToOne: false
            referencedRelation: "physical_count_sheets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "physical_count_sheet_lines_gl_variance_account_id_fkey"
            columns: ["gl_variance_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "physical_count_sheet_lines_inventory_cost_layer_id_fkey"
            columns: ["inventory_cost_layer_id"]
            isOneToOne: false
            referencedRelation: "inventory_cost_layers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "physical_count_sheet_lines_inventory_cost_layer_id_fkey"
            columns: ["inventory_cost_layer_id"]
            isOneToOne: false
            referencedRelation: "vw_available_inventory_identities"
            referencedColumns: ["inventory_cost_layer_id"]
          },
          {
            foreignKeyName: "physical_count_sheet_lines_inventory_transaction_id_fkey"
            columns: ["inventory_transaction_id"]
            isOneToOne: false
            referencedRelation: "inventory_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "physical_count_sheet_lines_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
        ]
      }
      physical_count_sheets: {
        Row: {
          branch_id: string | null
          company_id: string
          count_date: string
          count_number: string
          created_at: string
          created_by: string | null
          fiscal_period_id: string | null
          id: string
          journal_entry_id: string | null
          notes: string | null
          posted_at: string | null
          posted_by: string | null
          status: string
          updated_at: string
          updated_by: string | null
          warehouse_id: string
        }
        Insert: {
          branch_id?: string | null
          company_id: string
          count_date: string
          count_number: string
          created_at?: string
          created_by?: string | null
          fiscal_period_id?: string | null
          id?: string
          journal_entry_id?: string | null
          notes?: string | null
          posted_at?: string | null
          posted_by?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
          warehouse_id: string
        }
        Update: {
          branch_id?: string | null
          company_id?: string
          count_date?: string
          count_number?: string
          created_at?: string
          created_by?: string | null
          fiscal_period_id?: string | null
          id?: string
          journal_entry_id?: string | null
          notes?: string | null
          posted_at?: string | null
          posted_by?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
          warehouse_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "physical_count_sheets_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "physical_count_sheets_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "physical_count_sheets_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "physical_count_sheets_fiscal_period_id_fkey"
            columns: ["fiscal_period_id"]
            isOneToOne: false
            referencedRelation: "fiscal_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "physical_count_sheets_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "physical_count_sheets_warehouse_id_fkey"
            columns: ["warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
        ]
      }
      projects: {
        Row: {
          branch_id: string | null
          company_id: string
          created_at: string
          created_by: string | null
          description: string | null
          id: string
          is_active: boolean
          manager_user_id: string | null
          parent_project_id: string | null
          project_code: string
          project_name: string
          project_status: string
          updated_at: string
          updated_by: string | null
          valid_from: string | null
          valid_to: string | null
        }
        Insert: {
          branch_id?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          is_active?: boolean
          manager_user_id?: string | null
          parent_project_id?: string | null
          project_code: string
          project_name: string
          project_status?: string
          updated_at?: string
          updated_by?: string | null
          valid_from?: string | null
          valid_to?: string | null
        }
        Update: {
          branch_id?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          is_active?: boolean
          manager_user_id?: string | null
          parent_project_id?: string | null
          project_code?: string
          project_name?: string
          project_status?: string
          updated_at?: string
          updated_by?: string | null
          valid_from?: string | null
          valid_to?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "projects_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "projects_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "projects_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "projects_parent_project_id_fkey"
            columns: ["parent_project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
        ]
      }
      pt_returns: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          filed_date: string | null
          gross_sales_exempt: number
          gross_sales_zero_rated: number
          id: string
          period_quarter: number
          period_year: number
          pt_due: number
          pt_paid_prior_quarters: number
          pt_rate: number
          pt_still_due: number
          reference_no: string | null
          remarks: string | null
          status: string
          taxable_base: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          filed_date?: string | null
          gross_sales_exempt?: number
          gross_sales_zero_rated?: number
          id?: string
          period_quarter: number
          period_year: number
          pt_due?: number
          pt_paid_prior_quarters?: number
          pt_rate?: number
          pt_still_due?: number
          reference_no?: string | null
          remarks?: string | null
          status?: string
          taxable_base?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          filed_date?: string | null
          gross_sales_exempt?: number
          gross_sales_zero_rated?: number
          id?: string
          period_quarter?: number
          period_year?: number
          pt_due?: number
          pt_paid_prior_quarters?: number
          pt_rate?: number
          pt_still_due?: number
          reference_no?: string | null
          remarks?: string | null
          status?: string
          taxable_base?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "pt_returns_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pt_returns_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      purchase_order_lines: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          description: string
          id: string
          item_id: string | null
          line_number: number
          po_id: string
          quantity: number
          total_amount: number
          unit_price: number
          uom_id: string | null
          updated_at: string
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          description: string
          id?: string
          item_id?: string | null
          line_number: number
          po_id: string
          quantity?: number
          total_amount?: number
          unit_price?: number
          uom_id?: string | null
          updated_at?: string
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          description?: string
          id?: string
          item_id?: string | null
          line_number?: number
          po_id?: string
          quantity?: number
          total_amount?: number
          unit_price?: number
          uom_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "purchase_order_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_order_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "purchase_order_lines_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_order_lines_po_id_fkey"
            columns: ["po_id"]
            isOneToOne: false
            referencedRelation: "purchase_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_order_lines_uom_id_fkey"
            columns: ["uom_id"]
            isOneToOne: false
            referencedRelation: "units_of_measure"
            referencedColumns: ["id"]
          },
        ]
      }
      purchase_orders: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          branch_id: string | null
          company_id: string
          cost_center_id: string | null
          created_at: string
          created_by: string | null
          currency_code: string
          delivery_address: string | null
          department_id: string | null
          expected_date: string | null
          id: string
          notes: string | null
          payment_terms_id: string | null
          po_date: string
          po_number: string
          status: string
          supplier_id: string
          supplier_name_snapshot: string
          supplier_tin_snapshot: string | null
          total_amount: number
          updated_at: string
          updated_by: string | null
          warehouse_id: string | null
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          branch_id?: string | null
          company_id: string
          cost_center_id?: string | null
          created_at?: string
          created_by?: string | null
          currency_code?: string
          delivery_address?: string | null
          department_id?: string | null
          expected_date?: string | null
          id?: string
          notes?: string | null
          payment_terms_id?: string | null
          po_date: string
          po_number: string
          status?: string
          supplier_id: string
          supplier_name_snapshot: string
          supplier_tin_snapshot?: string | null
          total_amount?: number
          updated_at?: string
          updated_by?: string | null
          warehouse_id?: string | null
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          branch_id?: string | null
          company_id?: string
          cost_center_id?: string | null
          created_at?: string
          created_by?: string | null
          currency_code?: string
          delivery_address?: string | null
          department_id?: string | null
          expected_date?: string | null
          id?: string
          notes?: string | null
          payment_terms_id?: string | null
          po_date?: string
          po_number?: string
          status?: string
          supplier_id?: string
          supplier_name_snapshot?: string
          supplier_tin_snapshot?: string | null
          total_amount?: number
          updated_at?: string
          updated_by?: string | null
          warehouse_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "purchase_orders_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_orders_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_orders_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "purchase_orders_cost_center_id_fkey"
            columns: ["cost_center_id"]
            isOneToOne: false
            referencedRelation: "cost_centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_orders_department_id_fkey"
            columns: ["department_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_orders_payment_terms_id_fkey"
            columns: ["payment_terms_id"]
            isOneToOne: false
            referencedRelation: "payment_terms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_orders_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_orders_warehouse_id_fkey"
            columns: ["warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
        ]
      }
      purchase_return_lines: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          description: string
          id: string
          inventory_cost: number | null
          inventory_cost_layer_id: string | null
          inventory_transaction_id: string | null
          item_id: string | null
          line_number: number
          lot_number: string | null
          max_qty: number
          reason: string | null
          return_id: string
          return_qty: number
          rr_line_id: string | null
          serial_number: string | null
          unit_cost: number | null
          unit_price: number
          uom_id: string | null
          updated_at: string
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          description: string
          id?: string
          inventory_cost?: number | null
          inventory_cost_layer_id?: string | null
          inventory_transaction_id?: string | null
          item_id?: string | null
          line_number: number
          lot_number?: string | null
          max_qty?: number
          reason?: string | null
          return_id: string
          return_qty?: number
          rr_line_id?: string | null
          serial_number?: string | null
          unit_cost?: number | null
          unit_price?: number
          uom_id?: string | null
          updated_at?: string
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          description?: string
          id?: string
          inventory_cost?: number | null
          inventory_cost_layer_id?: string | null
          inventory_transaction_id?: string | null
          item_id?: string | null
          line_number?: number
          lot_number?: string | null
          max_qty?: number
          reason?: string | null
          return_id?: string
          return_qty?: number
          rr_line_id?: string | null
          serial_number?: string | null
          unit_cost?: number | null
          unit_price?: number
          uom_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "purchase_return_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_return_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "purchase_return_lines_inventory_cost_layer_id_fkey"
            columns: ["inventory_cost_layer_id"]
            isOneToOne: false
            referencedRelation: "inventory_cost_layers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_return_lines_inventory_cost_layer_id_fkey"
            columns: ["inventory_cost_layer_id"]
            isOneToOne: false
            referencedRelation: "vw_available_inventory_identities"
            referencedColumns: ["inventory_cost_layer_id"]
          },
          {
            foreignKeyName: "purchase_return_lines_inventory_transaction_id_fkey"
            columns: ["inventory_transaction_id"]
            isOneToOne: false
            referencedRelation: "inventory_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_return_lines_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_return_lines_return_id_fkey"
            columns: ["return_id"]
            isOneToOne: false
            referencedRelation: "purchase_returns"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_return_lines_rr_line_id_fkey"
            columns: ["rr_line_id"]
            isOneToOne: false
            referencedRelation: "receiving_report_lines"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_return_lines_uom_id_fkey"
            columns: ["uom_id"]
            isOneToOne: false
            referencedRelation: "units_of_measure"
            referencedColumns: ["id"]
          },
        ]
      }
      purchase_returns: {
        Row: {
          branch_id: string | null
          company_id: string
          created_at: string
          created_by: string | null
          id: string
          journal_entry_id: string | null
          remarks: string | null
          return_date: string
          return_number: string
          rr_id: string
          status: string
          supplier_id: string
          supplier_name_snapshot: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          branch_id?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          id?: string
          journal_entry_id?: string | null
          remarks?: string | null
          return_date: string
          return_number: string
          rr_id: string
          status?: string
          supplier_id: string
          supplier_name_snapshot: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          branch_id?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          id?: string
          journal_entry_id?: string | null
          remarks?: string | null
          return_date?: string
          return_number?: string
          rr_id?: string
          status?: string
          supplier_id?: string
          supplier_name_snapshot?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "purchase_returns_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_returns_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_returns_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "purchase_returns_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_returns_rr_id_fkey"
            columns: ["rr_id"]
            isOneToOne: false
            referencedRelation: "receiving_reports"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_returns_rr_id_fkey"
            columns: ["rr_id"]
            isOneToOne: false
            referencedRelation: "vw_rr_item_billing_progress"
            referencedColumns: ["rr_id"]
          },
          {
            foreignKeyName: "purchase_returns_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
      receipt_lines: {
        Row: {
          atc_code_id: string | null
          company_id: string
          created_at: string
          created_by: string | null
          cwt_amount: number
          cwt_source: string
          cwt_tax_base: number | null
          cwt_variance_reason: string | null
          forex_adjustment: number
          id: string
          invoice_id: string | null
          line_type: string
          opening_ar_line_id: string | null
          payment_amount: number
          receipt_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          atc_code_id?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          cwt_amount?: number
          cwt_source?: string
          cwt_tax_base?: number | null
          cwt_variance_reason?: string | null
          forex_adjustment?: number
          id?: string
          invoice_id?: string | null
          line_type?: string
          opening_ar_line_id?: string | null
          payment_amount?: number
          receipt_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          atc_code_id?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          cwt_amount?: number
          cwt_source?: string
          cwt_tax_base?: number | null
          cwt_variance_reason?: string | null
          forex_adjustment?: number
          id?: string
          invoice_id?: string | null
          line_type?: string
          opening_ar_line_id?: string | null
          payment_amount?: number
          receipt_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "receipt_lines_atc_code_id_fkey"
            columns: ["atc_code_id"]
            isOneToOne: false
            referencedRelation: "atc_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receipt_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receipt_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "receipt_lines_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "sales_invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receipt_lines_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "vw_sales_invoice_register"
            referencedColumns: ["invoice_id"]
          },
          {
            foreignKeyName: "receipt_lines_opening_ar_line_id_fkey"
            columns: ["opening_ar_line_id"]
            isOneToOne: false
            referencedRelation: "opening_balance_ar_lines"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receipt_lines_receipt_id_fkey"
            columns: ["receipt_id"]
            isOneToOne: false
            referencedRelation: "receipts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receipt_lines_receipt_id_fkey"
            columns: ["receipt_id"]
            isOneToOne: false
            referencedRelation: "vw_receipt_register"
            referencedColumns: ["receipt_id"]
          },
        ]
      }
      receipts: {
        Row: {
          bank_account_id: string | null
          branch_id: string
          company_id: string
          created_at: string
          created_by: string | null
          customer_id: string
          customer_name_snapshot: string
          customer_tin_snapshot: string
          id: string
          journal_entry_id: string | null
          payment_mode_id: string
          posted_at: string | null
          posted_by: string | null
          receipt_date: string
          receipt_number: string
          reference_number: string | null
          remarks: string | null
          status: string
          total_amount: number
          total_cwt: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          bank_account_id?: string | null
          branch_id: string
          company_id: string
          created_at?: string
          created_by?: string | null
          customer_id: string
          customer_name_snapshot?: string
          customer_tin_snapshot?: string
          id?: string
          journal_entry_id?: string | null
          payment_mode_id: string
          posted_at?: string | null
          posted_by?: string | null
          receipt_date?: string
          receipt_number: string
          reference_number?: string | null
          remarks?: string | null
          status?: string
          total_amount?: number
          total_cwt?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          bank_account_id?: string | null
          branch_id?: string
          company_id?: string
          created_at?: string
          created_by?: string | null
          customer_id?: string
          customer_name_snapshot?: string
          customer_tin_snapshot?: string
          id?: string
          journal_entry_id?: string | null
          payment_mode_id?: string
          posted_at?: string | null
          posted_by?: string | null
          receipt_date?: string
          receipt_number?: string
          reference_number?: string | null
          remarks?: string | null
          status?: string
          total_amount?: number
          total_cwt?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "receipts_bank_account_id_fkey"
            columns: ["bank_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receipts_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receipts_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receipts_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "receipts_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receipts_payment_mode_id_fkey"
            columns: ["payment_mode_id"]
            isOneToOne: false
            referencedRelation: "ref_payment_modes"
            referencedColumns: ["id"]
          },
        ]
      }
      receiving_report_lines: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          description: string
          id: string
          inventory_transaction_id: string | null
          item_id: string | null
          line_number: number
          lot_number: string | null
          ordered_qty: number
          po_line_id: string | null
          received_qty: number
          reject_qty: number
          rr_id: string
          serial_number: string | null
          unit_price: number
          uom_id: string | null
          updated_at: string
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          description: string
          id?: string
          inventory_transaction_id?: string | null
          item_id?: string | null
          line_number: number
          lot_number?: string | null
          ordered_qty?: number
          po_line_id?: string | null
          received_qty?: number
          reject_qty?: number
          rr_id: string
          serial_number?: string | null
          unit_price?: number
          uom_id?: string | null
          updated_at?: string
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          description?: string
          id?: string
          inventory_transaction_id?: string | null
          item_id?: string | null
          line_number?: number
          lot_number?: string | null
          ordered_qty?: number
          po_line_id?: string | null
          received_qty?: number
          reject_qty?: number
          rr_id?: string
          serial_number?: string | null
          unit_price?: number
          uom_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "receiving_report_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receiving_report_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "receiving_report_lines_inventory_transaction_id_fkey"
            columns: ["inventory_transaction_id"]
            isOneToOne: false
            referencedRelation: "inventory_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receiving_report_lines_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receiving_report_lines_po_line_id_fkey"
            columns: ["po_line_id"]
            isOneToOne: false
            referencedRelation: "purchase_order_lines"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receiving_report_lines_po_line_id_fkey"
            columns: ["po_line_id"]
            isOneToOne: false
            referencedRelation: "vw_po_line_receipt_progress"
            referencedColumns: ["po_line_id"]
          },
          {
            foreignKeyName: "receiving_report_lines_rr_id_fkey"
            columns: ["rr_id"]
            isOneToOne: false
            referencedRelation: "receiving_reports"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receiving_report_lines_rr_id_fkey"
            columns: ["rr_id"]
            isOneToOne: false
            referencedRelation: "vw_rr_item_billing_progress"
            referencedColumns: ["rr_id"]
          },
          {
            foreignKeyName: "receiving_report_lines_uom_id_fkey"
            columns: ["uom_id"]
            isOneToOne: false
            referencedRelation: "units_of_measure"
            referencedColumns: ["id"]
          },
        ]
      }
      receiving_reports: {
        Row: {
          branch_id: string | null
          company_id: string
          confirmed_at: string | null
          confirmed_by: string | null
          cost_center_id: string | null
          created_at: string
          created_by: string | null
          department_id: string | null
          fiscal_period_id: string | null
          id: string
          journal_entry_id: string | null
          po_id: string
          posted_at: string | null
          posted_by: string | null
          remarks: string | null
          rr_date: string
          rr_number: string
          status: string
          supplier_dr_no: string | null
          supplier_id: string
          supplier_name_snapshot: string
          updated_at: string
          updated_by: string | null
          void_memo: string | null
          void_reason_id: string | null
          warehouse_id: string | null
        }
        Insert: {
          branch_id?: string | null
          company_id: string
          confirmed_at?: string | null
          confirmed_by?: string | null
          cost_center_id?: string | null
          created_at?: string
          created_by?: string | null
          department_id?: string | null
          fiscal_period_id?: string | null
          id?: string
          journal_entry_id?: string | null
          po_id: string
          posted_at?: string | null
          posted_by?: string | null
          remarks?: string | null
          rr_date: string
          rr_number: string
          status?: string
          supplier_dr_no?: string | null
          supplier_id: string
          supplier_name_snapshot: string
          updated_at?: string
          updated_by?: string | null
          void_memo?: string | null
          void_reason_id?: string | null
          warehouse_id?: string | null
        }
        Update: {
          branch_id?: string | null
          company_id?: string
          confirmed_at?: string | null
          confirmed_by?: string | null
          cost_center_id?: string | null
          created_at?: string
          created_by?: string | null
          department_id?: string | null
          fiscal_period_id?: string | null
          id?: string
          journal_entry_id?: string | null
          po_id?: string
          posted_at?: string | null
          posted_by?: string | null
          remarks?: string | null
          rr_date?: string
          rr_number?: string
          status?: string
          supplier_dr_no?: string | null
          supplier_id?: string
          supplier_name_snapshot?: string
          updated_at?: string
          updated_by?: string | null
          void_memo?: string | null
          void_reason_id?: string | null
          warehouse_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "receiving_reports_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receiving_reports_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receiving_reports_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "receiving_reports_cost_center_id_fkey"
            columns: ["cost_center_id"]
            isOneToOne: false
            referencedRelation: "cost_centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receiving_reports_department_id_fkey"
            columns: ["department_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receiving_reports_fiscal_period_id_fkey"
            columns: ["fiscal_period_id"]
            isOneToOne: false
            referencedRelation: "fiscal_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receiving_reports_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receiving_reports_po_id_fkey"
            columns: ["po_id"]
            isOneToOne: false
            referencedRelation: "purchase_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receiving_reports_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receiving_reports_void_reason_id_fkey"
            columns: ["void_reason_id"]
            isOneToOne: false
            referencedRelation: "void_reason_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receiving_reports_warehouse_id_fkey"
            columns: ["warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
        ]
      }
      recurring_journal_template_lines: {
        Row: {
          account_id: string
          company_id: string
          created_at: string
          created_by: string | null
          credit_amount: number
          debit_amount: number
          description: string | null
          id: string
          line_number: number
          template_id: string
        }
        Insert: {
          account_id: string
          company_id: string
          created_at?: string
          created_by?: string | null
          credit_amount?: number
          debit_amount?: number
          description?: string | null
          id?: string
          line_number: number
          template_id: string
        }
        Update: {
          account_id?: string
          company_id?: string
          created_at?: string
          created_by?: string | null
          credit_amount?: number
          debit_amount?: number
          description?: string | null
          id?: string
          line_number?: number
          template_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "recurring_journal_template_lines_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recurring_journal_template_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recurring_journal_template_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "recurring_journal_template_lines_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "recurring_journal_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      recurring_journal_templates: {
        Row: {
          auto_reverse: boolean
          branch_id: string | null
          company_id: string
          created_at: string
          created_by: string | null
          day_of_month: number
          description: string | null
          end_date: string | null
          id: string
          is_active: boolean
          last_run_date: string | null
          next_run_date: string | null
          recurrence_type: string
          start_date: string
          template_name: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          auto_reverse?: boolean
          branch_id?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          day_of_month?: number
          description?: string | null
          end_date?: string | null
          id?: string
          is_active?: boolean
          last_run_date?: string | null
          next_run_date?: string | null
          recurrence_type?: string
          start_date: string
          template_name: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          auto_reverse?: boolean
          branch_id?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          day_of_month?: number
          description?: string | null
          end_date?: string | null
          id?: string
          is_active?: boolean
          last_run_date?: string | null
          next_run_date?: string | null
          recurrence_type?: string
          start_date?: string
          template_name?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "recurring_journal_templates_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recurring_journal_templates_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recurring_journal_templates_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      ref_banks: {
        Row: {
          bank_code: string
          bank_name: string
          created_at: string
          id: string
          is_active: boolean
          sort_order: number
          swift_code: string | null
        }
        Insert: {
          bank_code: string
          bank_name: string
          created_at?: string
          id?: string
          is_active?: boolean
          sort_order?: number
          swift_code?: string | null
        }
        Update: {
          bank_code?: string
          bank_name?: string
          created_at?: string
          id?: string
          is_active?: boolean
          sort_order?: number
          swift_code?: string | null
        }
        Relationships: []
      }
      ref_compliance_forms: {
        Row: {
          compliance_type: string
          created_at: string | null
          efps_eligible: boolean | null
          form_code: string
          form_name: string
          id: string
          is_active: boolean | null
          statutory_deadline_rule: string
        }
        Insert: {
          compliance_type: string
          created_at?: string | null
          efps_eligible?: boolean | null
          form_code: string
          form_name: string
          id?: string
          is_active?: boolean | null
          statutory_deadline_rule: string
        }
        Update: {
          compliance_type?: string
          created_at?: string | null
          efps_eligible?: boolean | null
          form_code?: string
          form_name?: string
          id?: string
          is_active?: boolean | null
          statutory_deadline_rule?: string
        }
        Relationships: []
      }
      ref_document_types: {
        Row: {
          category: string
          created_at: string | null
          document_code: string
          document_name: string
          id: string
          is_bir_registered: boolean | null
          sort_order: number
        }
        Insert: {
          category: string
          created_at?: string | null
          document_code: string
          document_name: string
          id?: string
          is_bir_registered?: boolean | null
          sort_order: number
        }
        Update: {
          category?: string
          created_at?: string | null
          document_code?: string
          document_name?: string
          id?: string
          is_bir_registered?: boolean | null
          sort_order?: number
        }
        Relationships: []
      }
      ref_feature_definitions: {
        Row: {
          always_enabled: boolean | null
          created_at: string | null
          description: string
          feature_key: string
          feature_name: string
          id: string
          is_active: boolean | null
          module_category: string
          sort_order: number
        }
        Insert: {
          always_enabled?: boolean | null
          created_at?: string | null
          description: string
          feature_key: string
          feature_name: string
          id?: string
          is_active?: boolean | null
          module_category: string
          sort_order: number
        }
        Update: {
          always_enabled?: boolean | null
          created_at?: string | null
          description?: string
          feature_key?: string
          feature_name?: string
          id?: string
          is_active?: boolean | null
          module_category?: string
          sort_order?: number
        }
        Relationships: []
      }
      ref_filing_artifact: {
        Row: {
          artifact_kind: string
          created_at: string
          form_code: string
          form_name: string
          group_dimensions: string[]
          is_active: boolean
          period_basis: string
          statutory_basis: string | null
          statutory_deadline_rule: string
        }
        Insert: {
          artifact_kind: string
          created_at?: string
          form_code: string
          form_name: string
          group_dimensions: string[]
          is_active?: boolean
          period_basis: string
          statutory_basis?: string | null
          statutory_deadline_rule: string
        }
        Update: {
          artifact_kind?: string
          created_at?: string
          form_code?: string
          form_name?: string
          group_dimensions?: string[]
          is_active?: boolean
          period_basis?: string
          statutory_basis?: string | null
          statutory_deadline_rule?: string
        }
        Relationships: []
      }
      ref_filing_artifact_kind: {
        Row: {
          form_code: string
          net_sign: number
          tax_kind: string
        }
        Insert: {
          form_code: string
          net_sign?: number
          tax_kind: string
        }
        Update: {
          form_code?: string
          net_sign?: number
          tax_kind?: string
        }
        Relationships: [
          {
            foreignKeyName: "ref_filing_artifact_kind_form_code_fkey"
            columns: ["form_code"]
            isOneToOne: false
            referencedRelation: "ref_filing_artifact"
            referencedColumns: ["form_code"]
          },
          {
            foreignKeyName: "ref_filing_artifact_kind_tax_kind_fkey"
            columns: ["tax_kind"]
            isOneToOne: false
            referencedRelation: "ref_tax_ledger_control"
            referencedColumns: ["tax_kind"]
          },
        ]
      }
      ref_filing_export_column: {
        Row: {
          column_header: string
          column_order: number
          export_format: string
          form_code: string
          source_field: string
          value_kind: string
        }
        Insert: {
          column_header: string
          column_order: number
          export_format: string
          form_code: string
          source_field: string
          value_kind?: string
        }
        Update: {
          column_header?: string
          column_order?: number
          export_format?: string
          form_code?: string
          source_field?: string
          value_kind?: string
        }
        Relationships: [
          {
            foreignKeyName: "ref_filing_export_column_form_code_fkey"
            columns: ["form_code"]
            isOneToOne: false
            referencedRelation: "ref_filing_artifact"
            referencedColumns: ["form_code"]
          },
        ]
      }
      ref_inventory_event_source_types: {
        Row: {
          correction_placement_class: string
          created_at: string
          document_order_key_algorithm: string
          event_effect_map: Json
          is_certification_only: boolean
          is_production_enabled: boolean
          line_order_authority: string
          occurrence_semantics: string
          owner_engine: string
          removal_phase: string | null
          same_time_class: string
          source_document_type: string
        }
        Insert: {
          correction_placement_class: string
          created_at?: string
          document_order_key_algorithm: string
          event_effect_map: Json
          is_certification_only?: boolean
          is_production_enabled?: boolean
          line_order_authority: string
          occurrence_semantics: string
          owner_engine: string
          removal_phase?: string | null
          same_time_class: string
          source_document_type: string
        }
        Update: {
          correction_placement_class?: string
          created_at?: string
          document_order_key_algorithm?: string
          event_effect_map?: Json
          is_certification_only?: boolean
          is_production_enabled?: boolean
          line_order_authority?: string
          occurrence_semantics?: string
          owner_engine?: string
          removal_phase?: string | null
          same_time_class?: string
          source_document_type?: string
        }
        Relationships: []
      }
      ref_mapping_key: {
        Row: {
          created_at: string
          description: string
          expected_account_type: string | null
          is_active: boolean
          key_code: string
        }
        Insert: {
          created_at?: string
          description: string
          expected_account_type?: string | null
          is_active?: boolean
          key_code: string
        }
        Update: {
          created_at?: string
          description?: string
          expected_account_type?: string | null
          is_active?: boolean
          key_code?: string
        }
        Relationships: []
      }
      ref_payment_modes: {
        Row: {
          code: string
          id: string
          is_active: boolean
          name: string
          sort_order: number
        }
        Insert: {
          code: string
          id?: string
          is_active?: boolean
          name: string
          sort_order?: number
        }
        Update: {
          code?: string
          id?: string
          is_active?: boolean
          name?: string
          sort_order?: number
        }
        Relationships: []
      }
      ref_posting_source_types: {
        Row: {
          allows_multiple_journal_entries: boolean
          display_name: string
          document_date_column: unknown
          document_number_column: unknown
          document_type: string
          is_active: boolean
          route_path: string
          source_table: unknown
          status_column: unknown
        }
        Insert: {
          allows_multiple_journal_entries?: boolean
          display_name: string
          document_date_column?: unknown
          document_number_column?: unknown
          document_type: string
          is_active?: boolean
          route_path: string
          source_table?: unknown
          status_column?: unknown
        }
        Update: {
          allows_multiple_journal_entries?: boolean
          display_name?: string
          document_date_column?: unknown
          document_number_column?: unknown
          document_type?: string
          is_active?: boolean
          route_path?: string
          source_table?: unknown
          status_column?: unknown
        }
        Relationships: []
      }
      ref_rdo_codes: {
        Row: {
          created_at: string | null
          id: string
          rdo_code: string
          rdo_name: string
          updated_at: string | null
        }
        Insert: {
          created_at?: string | null
          id?: string
          rdo_code: string
          rdo_name: string
          updated_at?: string | null
        }
        Update: {
          created_at?: string | null
          id?: string
          rdo_code?: string
          rdo_name?: string
          updated_at?: string | null
        }
        Relationships: []
      }
      ref_reason_codes: {
        Row: {
          applies_to: string
          code: string
          description: string
          id: string
          is_active: boolean
          sort_order: number
        }
        Insert: {
          applies_to: string
          code: string
          description: string
          id?: string
          is_active?: boolean
          sort_order?: number
        }
        Update: {
          applies_to?: string
          code?: string
          description?: string
          id?: string
          is_active?: boolean
          sort_order?: number
        }
        Relationships: []
      }
      ref_tax_ledger_control: {
        Row: {
          created_at: string
          description: string
          excluded_reference_types: string[]
          included_je_statuses: string[]
          is_active: boolean
          mapping_key: string
          normal_balance: string
          tax_kind: string
        }
        Insert: {
          created_at?: string
          description: string
          excluded_reference_types?: string[]
          included_je_statuses?: string[]
          is_active?: boolean
          mapping_key: string
          normal_balance: string
          tax_kind: string
        }
        Update: {
          created_at?: string
          description?: string
          excluded_reference_types?: string[]
          included_je_statuses?: string[]
          is_active?: boolean
          mapping_key?: string
          normal_balance?: string
          tax_kind?: string
        }
        Relationships: [
          {
            foreignKeyName: "ref_tax_ledger_control_mapping_key_fkey"
            columns: ["mapping_key"]
            isOneToOne: false
            referencedRelation: "ref_mapping_key"
            referencedColumns: ["key_code"]
          },
        ]
      }
      report_snapshots: {
        Row: {
          company_id: string
          created_at: string
          generated_at: string
          generated_by: string | null
          id: string
          period_end: string
          period_start: string
          report_payload: Json
          report_type: string
          snapshot_status: string
          snapshot_version: number
          source_hash: string
          source_id: string
          source_payload: Json
          source_row_count: number
          source_table: string
        }
        Insert: {
          company_id: string
          created_at?: string
          generated_at?: string
          generated_by?: string | null
          id?: string
          period_end: string
          period_start: string
          report_payload: Json
          report_type: string
          snapshot_status: string
          snapshot_version?: number
          source_hash: string
          source_id: string
          source_payload: Json
          source_row_count?: number
          source_table: string
        }
        Update: {
          company_id?: string
          created_at?: string
          generated_at?: string
          generated_by?: string | null
          id?: string
          period_end?: string
          period_start?: string
          report_payload?: Json
          report_type?: string
          snapshot_status?: string
          snapshot_version?: number
          source_hash?: string
          source_id?: string
          source_payload?: Json
          source_row_count?: number
          source_table?: string
        }
        Relationships: [
          {
            foreignKeyName: "report_snapshots_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "report_snapshots_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      revenue_recognition_entries: {
        Row: {
          amount: number
          company_id: string
          created_at: string
          entry_date: string
          id: string
          je_id: string | null
          period_number: number
          schedule_id: string
          status: string
        }
        Insert: {
          amount: number
          company_id: string
          created_at?: string
          entry_date: string
          id?: string
          je_id?: string | null
          period_number: number
          schedule_id: string
          status?: string
        }
        Update: {
          amount?: number
          company_id?: string
          created_at?: string
          entry_date?: string
          id?: string
          je_id?: string | null
          period_number?: number
          schedule_id?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "revenue_recognition_entries_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "revenue_recognition_entries_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "revenue_recognition_entries_je_id_fkey"
            columns: ["je_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "revenue_recognition_entries_schedule_id_fkey"
            columns: ["schedule_id"]
            isOneToOne: false
            referencedRelation: "revenue_recognition_schedules"
            referencedColumns: ["id"]
          },
        ]
      }
      revenue_recognition_schedules: {
        Row: {
          branch_id: string | null
          company_id: string
          created_at: string
          created_by: string | null
          deferred_revenue_account_id: string
          description: string | null
          id: string
          posted_periods: number
          revenue_account_id: string
          schedule_name: string
          start_date: string
          status: string
          total_amount: number
          total_periods: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          branch_id?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          deferred_revenue_account_id: string
          description?: string | null
          id?: string
          posted_periods?: number
          revenue_account_id: string
          schedule_name: string
          start_date: string
          status?: string
          total_amount: number
          total_periods: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          branch_id?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          deferred_revenue_account_id?: string
          description?: string | null
          id?: string
          posted_periods?: number
          revenue_account_id?: string
          schedule_name?: string
          start_date?: string
          status?: string
          total_amount?: number
          total_periods?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "revenue_recognition_schedules_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "revenue_recognition_schedules_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "revenue_recognition_schedules_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "revenue_recognition_schedules_deferred_revenue_account_id_fkey"
            columns: ["deferred_revenue_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "revenue_recognition_schedules_revenue_account_id_fkey"
            columns: ["revenue_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      sales_invoice_lines: {
        Row: {
          cogs_account_id: string | null
          company_id: string
          cost_center_id: string | null
          created_at: string
          created_by: string | null
          department_id: string | null
          description: string
          discount_amount: number
          discount_percent: number
          functional_entity_id: string | null
          id: string
          inventory_account_id: string | null
          inventory_cost: number | null
          inventory_cost_layer_id: string | null
          inventory_transaction_id: string | null
          item_id: string | null
          line_number: number
          location_id: string | null
          lot_number: string | null
          net_amount: number
          percentage_tax_amount: number | null
          percentage_tax_base: number | null
          percentage_tax_code_id: string | null
          percentage_tax_rate: number | null
          project_id: string | null
          quantity: number
          remarks: string | null
          revenue_account_id: string | null
          sales_invoice_id: string
          salesperson_id: string | null
          serial_number: string | null
          source_document_type: string | null
          source_line_id: string | null
          total_amount: number
          unit_cost: number | null
          unit_price: number
          uom_id: string | null
          updated_at: string
          updated_by: string | null
          vat_amount: number
          vat_code_id: string | null
          warehouse_id: string | null
          withholding_atc_code_id: string | null
          withholding_tax_amount: number | null
          withholding_tax_base: number | null
          withholding_tax_rate: number | null
        }
        Insert: {
          cogs_account_id?: string | null
          company_id: string
          cost_center_id?: string | null
          created_at?: string
          created_by?: string | null
          department_id?: string | null
          description: string
          discount_amount?: number
          discount_percent?: number
          functional_entity_id?: string | null
          id?: string
          inventory_account_id?: string | null
          inventory_cost?: number | null
          inventory_cost_layer_id?: string | null
          inventory_transaction_id?: string | null
          item_id?: string | null
          line_number: number
          location_id?: string | null
          lot_number?: string | null
          net_amount?: number
          percentage_tax_amount?: number | null
          percentage_tax_base?: number | null
          percentage_tax_code_id?: string | null
          percentage_tax_rate?: number | null
          project_id?: string | null
          quantity?: number
          remarks?: string | null
          revenue_account_id?: string | null
          sales_invoice_id: string
          salesperson_id?: string | null
          serial_number?: string | null
          source_document_type?: string | null
          source_line_id?: string | null
          total_amount?: number
          unit_cost?: number | null
          unit_price?: number
          uom_id?: string | null
          updated_at?: string
          updated_by?: string | null
          vat_amount?: number
          vat_code_id?: string | null
          warehouse_id?: string | null
          withholding_atc_code_id?: string | null
          withholding_tax_amount?: number | null
          withholding_tax_base?: number | null
          withholding_tax_rate?: number | null
        }
        Update: {
          cogs_account_id?: string | null
          company_id?: string
          cost_center_id?: string | null
          created_at?: string
          created_by?: string | null
          department_id?: string | null
          description?: string
          discount_amount?: number
          discount_percent?: number
          functional_entity_id?: string | null
          id?: string
          inventory_account_id?: string | null
          inventory_cost?: number | null
          inventory_cost_layer_id?: string | null
          inventory_transaction_id?: string | null
          item_id?: string | null
          line_number?: number
          location_id?: string | null
          lot_number?: string | null
          net_amount?: number
          percentage_tax_amount?: number | null
          percentage_tax_base?: number | null
          percentage_tax_code_id?: string | null
          percentage_tax_rate?: number | null
          project_id?: string | null
          quantity?: number
          remarks?: string | null
          revenue_account_id?: string | null
          sales_invoice_id?: string
          salesperson_id?: string | null
          serial_number?: string | null
          source_document_type?: string | null
          source_line_id?: string | null
          total_amount?: number
          unit_cost?: number | null
          unit_price?: number
          uom_id?: string | null
          updated_at?: string
          updated_by?: string | null
          vat_amount?: number
          vat_code_id?: string | null
          warehouse_id?: string | null
          withholding_atc_code_id?: string | null
          withholding_tax_amount?: number | null
          withholding_tax_base?: number | null
          withholding_tax_rate?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "sales_invoice_lines_cogs_account_id_fkey"
            columns: ["cogs_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoice_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoice_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "sales_invoice_lines_cost_center_id_fkey"
            columns: ["cost_center_id"]
            isOneToOne: false
            referencedRelation: "cost_centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoice_lines_department_id_fkey"
            columns: ["department_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoice_lines_functional_entity_id_fkey"
            columns: ["functional_entity_id"]
            isOneToOne: false
            referencedRelation: "functional_entities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoice_lines_inventory_account_id_fkey"
            columns: ["inventory_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoice_lines_inventory_cost_layer_id_fkey"
            columns: ["inventory_cost_layer_id"]
            isOneToOne: false
            referencedRelation: "inventory_cost_layers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoice_lines_inventory_cost_layer_id_fkey"
            columns: ["inventory_cost_layer_id"]
            isOneToOne: false
            referencedRelation: "vw_available_inventory_identities"
            referencedColumns: ["inventory_cost_layer_id"]
          },
          {
            foreignKeyName: "sales_invoice_lines_inventory_transaction_id_fkey"
            columns: ["inventory_transaction_id"]
            isOneToOne: false
            referencedRelation: "inventory_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoice_lines_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoice_lines_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoice_lines_percentage_tax_code_id_fkey"
            columns: ["percentage_tax_code_id"]
            isOneToOne: false
            referencedRelation: "percentage_tax_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoice_lines_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoice_lines_revenue_account_id_fkey"
            columns: ["revenue_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoice_lines_sales_invoice_id_fkey"
            columns: ["sales_invoice_id"]
            isOneToOne: false
            referencedRelation: "sales_invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoice_lines_sales_invoice_id_fkey"
            columns: ["sales_invoice_id"]
            isOneToOne: false
            referencedRelation: "vw_sales_invoice_register"
            referencedColumns: ["invoice_id"]
          },
          {
            foreignKeyName: "sales_invoice_lines_salesperson_id_fkey"
            columns: ["salesperson_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoice_lines_uom_id_fkey"
            columns: ["uom_id"]
            isOneToOne: false
            referencedRelation: "units_of_measure"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoice_lines_vat_code_id_fkey"
            columns: ["vat_code_id"]
            isOneToOne: false
            referencedRelation: "vat_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoice_lines_warehouse_id_fkey"
            columns: ["warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoice_lines_withholding_atc_code_id_fkey"
            columns: ["withholding_atc_code_id"]
            isOneToOne: false
            referencedRelation: "atc_codes"
            referencedColumns: ["id"]
          },
        ]
      }
      sales_invoices: {
        Row: {
          account_owner_id: string | null
          approved_at: string | null
          approved_by: string | null
          branch_id: string
          company_id: string
          cost_center_id: string | null
          created_at: string
          created_by: string | null
          currency_code: string
          customer_address_snapshot: string
          customer_id: string
          customer_name_snapshot: string
          customer_tin_snapshot: string
          cwt_amount_expected: number | null
          cwt_atc_code_id: string | null
          cwt_tax_base: number | null
          date: string
          department_id: string | null
          due_date: string | null
          fiscal_period_id: string | null
          functional_entity_id: string | null
          id: string
          is_cash_sale: boolean
          journal_entry_id: string | null
          location_id: string | null
          memo: string | null
          payment_terms_id: string | null
          posted_at: string | null
          posted_by: string | null
          project_id: string | null
          reference: string | null
          salesperson_id: string | null
          si_number: string
          status: string
          total_amount: number
          total_exempt_amount: number
          total_percentage_tax_amount: number
          total_taxable_amount: number
          total_vat_amount: number
          total_zero_rated_amount: number
          updated_at: string
          updated_by: string | null
          vat_price_basis: string
          void_reason_id: string | null
          warehouse_id: string | null
        }
        Insert: {
          account_owner_id?: string | null
          approved_at?: string | null
          approved_by?: string | null
          branch_id: string
          company_id: string
          cost_center_id?: string | null
          created_at?: string
          created_by?: string | null
          currency_code?: string
          customer_address_snapshot?: string
          customer_id: string
          customer_name_snapshot?: string
          customer_tin_snapshot?: string
          cwt_amount_expected?: number | null
          cwt_atc_code_id?: string | null
          cwt_tax_base?: number | null
          date?: string
          department_id?: string | null
          due_date?: string | null
          fiscal_period_id?: string | null
          functional_entity_id?: string | null
          id?: string
          is_cash_sale?: boolean
          journal_entry_id?: string | null
          location_id?: string | null
          memo?: string | null
          payment_terms_id?: string | null
          posted_at?: string | null
          posted_by?: string | null
          project_id?: string | null
          reference?: string | null
          salesperson_id?: string | null
          si_number: string
          status?: string
          total_amount?: number
          total_exempt_amount?: number
          total_percentage_tax_amount?: number
          total_taxable_amount?: number
          total_vat_amount?: number
          total_zero_rated_amount?: number
          updated_at?: string
          updated_by?: string | null
          vat_price_basis?: string
          void_reason_id?: string | null
          warehouse_id?: string | null
        }
        Update: {
          account_owner_id?: string | null
          approved_at?: string | null
          approved_by?: string | null
          branch_id?: string
          company_id?: string
          cost_center_id?: string | null
          created_at?: string
          created_by?: string | null
          currency_code?: string
          customer_address_snapshot?: string
          customer_id?: string
          customer_name_snapshot?: string
          customer_tin_snapshot?: string
          cwt_amount_expected?: number | null
          cwt_atc_code_id?: string | null
          cwt_tax_base?: number | null
          date?: string
          department_id?: string | null
          due_date?: string | null
          fiscal_period_id?: string | null
          functional_entity_id?: string | null
          id?: string
          is_cash_sale?: boolean
          journal_entry_id?: string | null
          location_id?: string | null
          memo?: string | null
          payment_terms_id?: string | null
          posted_at?: string | null
          posted_by?: string | null
          project_id?: string | null
          reference?: string | null
          salesperson_id?: string | null
          si_number?: string
          status?: string
          total_amount?: number
          total_exempt_amount?: number
          total_percentage_tax_amount?: number
          total_taxable_amount?: number
          total_vat_amount?: number
          total_zero_rated_amount?: number
          updated_at?: string
          updated_by?: string | null
          vat_price_basis?: string
          void_reason_id?: string | null
          warehouse_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sales_invoices_account_owner_id_fkey"
            columns: ["account_owner_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoices_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoices_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoices_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "sales_invoices_cost_center_id_fkey"
            columns: ["cost_center_id"]
            isOneToOne: false
            referencedRelation: "cost_centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoices_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoices_cwt_atc_code_id_fkey"
            columns: ["cwt_atc_code_id"]
            isOneToOne: false
            referencedRelation: "atc_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoices_department_id_fkey"
            columns: ["department_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoices_fiscal_period_id_fkey"
            columns: ["fiscal_period_id"]
            isOneToOne: false
            referencedRelation: "fiscal_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoices_functional_entity_id_fkey"
            columns: ["functional_entity_id"]
            isOneToOne: false
            referencedRelation: "functional_entities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoices_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoices_payment_terms_id_fkey"
            columns: ["payment_terms_id"]
            isOneToOne: false
            referencedRelation: "payment_terms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoices_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoices_salesperson_id_fkey"
            columns: ["salesperson_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoices_void_reason_id_fkey"
            columns: ["void_reason_id"]
            isOneToOne: false
            referencedRelation: "void_reason_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoices_warehouse_id_fkey"
            columns: ["warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
        ]
      }
      sales_order_lines: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          description: string
          discount_amount: number
          fulfilled_quantity: number
          id: string
          item_id: string | null
          line_number: number
          net_amount: number
          quantity: number
          quotation_line_id: string | null
          sales_order_id: string
          unit_price: number
          uom_id: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          description: string
          discount_amount?: number
          fulfilled_quantity?: number
          id?: string
          item_id?: string | null
          line_number?: number
          net_amount?: number
          quantity?: number
          quotation_line_id?: string | null
          sales_order_id: string
          unit_price?: number
          uom_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          description?: string
          discount_amount?: number
          fulfilled_quantity?: number
          id?: string
          item_id?: string | null
          line_number?: number
          net_amount?: number
          quantity?: number
          quotation_line_id?: string | null
          sales_order_id?: string
          unit_price?: number
          uom_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sales_order_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_order_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "sales_order_lines_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_order_lines_quotation_line_id_fkey"
            columns: ["quotation_line_id"]
            isOneToOne: false
            referencedRelation: "sales_quotation_lines"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_order_lines_sales_order_id_fkey"
            columns: ["sales_order_id"]
            isOneToOne: false
            referencedRelation: "sales_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_order_lines_uom_id_fkey"
            columns: ["uom_id"]
            isOneToOne: false
            referencedRelation: "units_of_measure"
            referencedColumns: ["id"]
          },
        ]
      }
      sales_orders: {
        Row: {
          approval_status: string
          approved_at: string | null
          approved_by: string | null
          branch_id: string
          company_id: string
          created_at: string
          created_by: string | null
          currency_code: string
          customer_id: string
          customer_name_snapshot: string
          customer_tin_snapshot: string
          expected_delivery_date: string | null
          fulfillment_status: string
          id: string
          quotation_id: string | null
          reference_number: string | null
          remarks: string | null
          so_date: string
          so_number: string
          total_amount: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          approval_status?: string
          approved_at?: string | null
          approved_by?: string | null
          branch_id: string
          company_id: string
          created_at?: string
          created_by?: string | null
          currency_code?: string
          customer_id: string
          customer_name_snapshot?: string
          customer_tin_snapshot?: string
          expected_delivery_date?: string | null
          fulfillment_status?: string
          id?: string
          quotation_id?: string | null
          reference_number?: string | null
          remarks?: string | null
          so_date?: string
          so_number: string
          total_amount?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          approval_status?: string
          approved_at?: string | null
          approved_by?: string | null
          branch_id?: string
          company_id?: string
          created_at?: string
          created_by?: string | null
          currency_code?: string
          customer_id?: string
          customer_name_snapshot?: string
          customer_tin_snapshot?: string
          expected_delivery_date?: string | null
          fulfillment_status?: string
          id?: string
          quotation_id?: string | null
          reference_number?: string | null
          remarks?: string | null
          so_date?: string
          so_number?: string
          total_amount?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sales_orders_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_orders_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_orders_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "sales_orders_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_orders_quotation_id_fkey"
            columns: ["quotation_id"]
            isOneToOne: false
            referencedRelation: "sales_quotations"
            referencedColumns: ["id"]
          },
        ]
      }
      sales_quotation_lines: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          description: string
          discount_amount: number
          id: string
          item_id: string | null
          line_number: number
          net_amount: number
          quantity: number
          quotation_id: string
          unit_price: number
          uom_id: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          description: string
          discount_amount?: number
          id?: string
          item_id?: string | null
          line_number?: number
          net_amount?: number
          quantity?: number
          quotation_id: string
          unit_price?: number
          uom_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          description?: string
          discount_amount?: number
          id?: string
          item_id?: string | null
          line_number?: number
          net_amount?: number
          quantity?: number
          quotation_id?: string
          unit_price?: number
          uom_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sales_quotation_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_quotation_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "sales_quotation_lines_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_quotation_lines_quotation_id_fkey"
            columns: ["quotation_id"]
            isOneToOne: false
            referencedRelation: "sales_quotations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_quotation_lines_uom_id_fkey"
            columns: ["uom_id"]
            isOneToOne: false
            referencedRelation: "units_of_measure"
            referencedColumns: ["id"]
          },
        ]
      }
      sales_quotations: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          branch_id: string
          company_id: string
          created_at: string
          created_by: string | null
          currency_code: string
          customer_id: string
          customer_name_snapshot: string
          customer_tin_snapshot: string
          id: string
          quotation_date: string
          quotation_number: string
          reference_number: string | null
          remarks: string | null
          status: string
          total_amount: number
          updated_at: string
          updated_by: string | null
          validity_date: string
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          branch_id: string
          company_id: string
          created_at?: string
          created_by?: string | null
          currency_code?: string
          customer_id: string
          customer_name_snapshot?: string
          customer_tin_snapshot?: string
          id?: string
          quotation_date?: string
          quotation_number: string
          reference_number?: string | null
          remarks?: string | null
          status?: string
          total_amount?: number
          updated_at?: string
          updated_by?: string | null
          validity_date: string
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          branch_id?: string
          company_id?: string
          created_at?: string
          created_by?: string | null
          currency_code?: string
          customer_id?: string
          customer_name_snapshot?: string
          customer_tin_snapshot?: string
          id?: string
          quotation_date?: string
          quotation_number?: string
          reference_number?: string | null
          remarks?: string | null
          status?: string
          total_amount?: number
          updated_at?: string
          updated_by?: string | null
          validity_date?: string
        }
        Relationships: [
          {
            foreignKeyName: "sales_quotations_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_quotations_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_quotations_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "sales_quotations_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
        ]
      }
      stock_adjustment_lines: {
        Row: {
          adjustment_id: string
          company_id: string
          gl_offset_account_id: string | null
          id: string
          inventory_cost_layer_id: string | null
          inventory_transaction_id: string | null
          item_id: string
          lot_number: string | null
          qty_adjusted: number
          qty_after: number
          qty_before: number
          serial_number: string | null
          total_cost_impact: number
          unit_cost: number
        }
        Insert: {
          adjustment_id: string
          company_id: string
          gl_offset_account_id?: string | null
          id?: string
          inventory_cost_layer_id?: string | null
          inventory_transaction_id?: string | null
          item_id: string
          lot_number?: string | null
          qty_adjusted: number
          qty_after: number
          qty_before?: number
          serial_number?: string | null
          total_cost_impact?: number
          unit_cost?: number
        }
        Update: {
          adjustment_id?: string
          company_id?: string
          gl_offset_account_id?: string | null
          id?: string
          inventory_cost_layer_id?: string | null
          inventory_transaction_id?: string | null
          item_id?: string
          lot_number?: string | null
          qty_adjusted?: number
          qty_after?: number
          qty_before?: number
          serial_number?: string | null
          total_cost_impact?: number
          unit_cost?: number
        }
        Relationships: [
          {
            foreignKeyName: "stock_adjustment_lines_adjustment_id_fkey"
            columns: ["adjustment_id"]
            isOneToOne: false
            referencedRelation: "stock_adjustments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_adjustment_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_adjustment_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "stock_adjustment_lines_gl_offset_account_id_fkey"
            columns: ["gl_offset_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_adjustment_lines_inventory_cost_layer_id_fkey"
            columns: ["inventory_cost_layer_id"]
            isOneToOne: false
            referencedRelation: "inventory_cost_layers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_adjustment_lines_inventory_cost_layer_id_fkey"
            columns: ["inventory_cost_layer_id"]
            isOneToOne: false
            referencedRelation: "vw_available_inventory_identities"
            referencedColumns: ["inventory_cost_layer_id"]
          },
          {
            foreignKeyName: "stock_adjustment_lines_inventory_transaction_id_fkey"
            columns: ["inventory_transaction_id"]
            isOneToOne: false
            referencedRelation: "inventory_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_adjustment_lines_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
        ]
      }
      stock_adjustments: {
        Row: {
          adjustment_date: string
          adjustment_number: string
          branch_id: string | null
          company_id: string
          created_at: string
          created_by: string | null
          fiscal_period_id: string | null
          id: string
          journal_entry_id: string | null
          notes: string | null
          posted_at: string | null
          posted_by: string | null
          reason: string
          status: string
          updated_at: string
          updated_by: string | null
          warehouse_id: string
        }
        Insert: {
          adjustment_date: string
          adjustment_number: string
          branch_id?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          fiscal_period_id?: string | null
          id?: string
          journal_entry_id?: string | null
          notes?: string | null
          posted_at?: string | null
          posted_by?: string | null
          reason: string
          status?: string
          updated_at?: string
          updated_by?: string | null
          warehouse_id: string
        }
        Update: {
          adjustment_date?: string
          adjustment_number?: string
          branch_id?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          fiscal_period_id?: string | null
          id?: string
          journal_entry_id?: string | null
          notes?: string | null
          posted_at?: string | null
          posted_by?: string | null
          reason?: string
          status?: string
          updated_at?: string
          updated_by?: string | null
          warehouse_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "stock_adjustments_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_adjustments_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_adjustments_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "stock_adjustments_fiscal_period_id_fkey"
            columns: ["fiscal_period_id"]
            isOneToOne: false
            referencedRelation: "fiscal_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_adjustments_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_adjustments_warehouse_id_fkey"
            columns: ["warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
        ]
      }
      stock_balances: {
        Row: {
          company_id: string
          id: string
          item_id: string
          last_issue_date: string | null
          last_receipt_date: string | null
          projection_authority: string
          projection_fingerprint: string | null
          projection_version_id: string | null
          projection_watermark_sequence: number | null
          qty_on_hand: number
          qty_reserved: number
          total_cost: number
          updated_at: string
          wac_unit_cost: number
          warehouse_id: string
        }
        Insert: {
          company_id: string
          id?: string
          item_id: string
          last_issue_date?: string | null
          last_receipt_date?: string | null
          projection_authority?: string
          projection_fingerprint?: string | null
          projection_version_id?: string | null
          projection_watermark_sequence?: number | null
          qty_on_hand?: number
          qty_reserved?: number
          total_cost?: number
          updated_at?: string
          wac_unit_cost?: number
          warehouse_id: string
        }
        Update: {
          company_id?: string
          id?: string
          item_id?: string
          last_issue_date?: string | null
          last_receipt_date?: string | null
          projection_authority?: string
          projection_fingerprint?: string | null
          projection_version_id?: string | null
          projection_watermark_sequence?: number | null
          qty_on_hand?: number
          qty_reserved?: number
          total_cost?: number
          updated_at?: string
          wac_unit_cost?: number
          warehouse_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "stock_balances_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_balances_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "stock_balances_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_balances_projection_version_id_fkey"
            columns: ["projection_version_id"]
            isOneToOne: false
            referencedRelation: "inventory_projection_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_balances_warehouse_id_fkey"
            columns: ["warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
        ]
      }
      stock_transfer_lines: {
        Row: {
          company_id: string
          destination_inventory_transaction_id: string | null
          id: string
          inventory_cost_layer_id: string | null
          item_id: string
          lot_number: string | null
          qty_transferred: number
          serial_number: string | null
          source_inventory_transaction_id: string | null
          total_cost: number
          transfer_id: string
          unit_cost: number
        }
        Insert: {
          company_id: string
          destination_inventory_transaction_id?: string | null
          id?: string
          inventory_cost_layer_id?: string | null
          item_id: string
          lot_number?: string | null
          qty_transferred: number
          serial_number?: string | null
          source_inventory_transaction_id?: string | null
          total_cost?: number
          transfer_id: string
          unit_cost?: number
        }
        Update: {
          company_id?: string
          destination_inventory_transaction_id?: string | null
          id?: string
          inventory_cost_layer_id?: string | null
          item_id?: string
          lot_number?: string | null
          qty_transferred?: number
          serial_number?: string | null
          source_inventory_transaction_id?: string | null
          total_cost?: number
          transfer_id?: string
          unit_cost?: number
        }
        Relationships: [
          {
            foreignKeyName: "stock_transfer_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_transfer_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "stock_transfer_lines_destination_inventory_transaction_id_fkey"
            columns: ["destination_inventory_transaction_id"]
            isOneToOne: false
            referencedRelation: "inventory_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_transfer_lines_inventory_cost_layer_id_fkey"
            columns: ["inventory_cost_layer_id"]
            isOneToOne: false
            referencedRelation: "inventory_cost_layers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_transfer_lines_inventory_cost_layer_id_fkey"
            columns: ["inventory_cost_layer_id"]
            isOneToOne: false
            referencedRelation: "vw_available_inventory_identities"
            referencedColumns: ["inventory_cost_layer_id"]
          },
          {
            foreignKeyName: "stock_transfer_lines_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_transfer_lines_source_inventory_transaction_id_fkey"
            columns: ["source_inventory_transaction_id"]
            isOneToOne: false
            referencedRelation: "inventory_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_transfer_lines_transfer_id_fkey"
            columns: ["transfer_id"]
            isOneToOne: false
            referencedRelation: "stock_transfers"
            referencedColumns: ["id"]
          },
        ]
      }
      stock_transfers: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          fiscal_period_id: string | null
          from_warehouse_id: string
          id: string
          journal_entry_id: string | null
          notes: string | null
          posted_at: string | null
          posted_by: string | null
          status: string
          to_warehouse_id: string
          transfer_date: string
          transfer_number: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          fiscal_period_id?: string | null
          from_warehouse_id: string
          id?: string
          journal_entry_id?: string | null
          notes?: string | null
          posted_at?: string | null
          posted_by?: string | null
          status?: string
          to_warehouse_id: string
          transfer_date: string
          transfer_number: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          fiscal_period_id?: string | null
          from_warehouse_id?: string
          id?: string
          journal_entry_id?: string | null
          notes?: string | null
          posted_at?: string | null
          posted_by?: string | null
          status?: string
          to_warehouse_id?: string
          transfer_date?: string
          transfer_number?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "stock_transfers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_transfers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "stock_transfers_fiscal_period_id_fkey"
            columns: ["fiscal_period_id"]
            isOneToOne: false
            referencedRelation: "fiscal_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_transfers_from_warehouse_id_fkey"
            columns: ["from_warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_transfers_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_transfers_to_warehouse_id_fkey"
            columns: ["to_warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
        ]
      }
      supplier_bank_accounts: {
        Row: {
          account_name: string
          account_number: string
          account_type: string
          bank_branch: string | null
          bank_id: string
          company_id: string
          created_at: string
          created_by: string | null
          id: string
          is_active: boolean
          is_default: boolean
          notes: string | null
          supplier_id: string
          swift_code: string | null
          updated_at: string
          updated_by: string | null
          verification_status: string
          verified_at: string | null
          verified_by: string | null
        }
        Insert: {
          account_name: string
          account_number: string
          account_type?: string
          bank_branch?: string | null
          bank_id: string
          company_id: string
          created_at?: string
          created_by?: string | null
          id?: string
          is_active?: boolean
          is_default?: boolean
          notes?: string | null
          supplier_id: string
          swift_code?: string | null
          updated_at?: string
          updated_by?: string | null
          verification_status?: string
          verified_at?: string | null
          verified_by?: string | null
        }
        Update: {
          account_name?: string
          account_number?: string
          account_type?: string
          bank_branch?: string | null
          bank_id?: string
          company_id?: string
          created_at?: string
          created_by?: string | null
          id?: string
          is_active?: boolean
          is_default?: boolean
          notes?: string | null
          supplier_id?: string
          swift_code?: string | null
          updated_at?: string
          updated_by?: string | null
          verification_status?: string
          verified_at?: string | null
          verified_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "supplier_bank_accounts_bank_id_fkey"
            columns: ["bank_id"]
            isOneToOne: false
            referencedRelation: "ref_banks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_bank_accounts_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_bank_accounts_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "supplier_bank_accounts_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
      supplier_debit_memo_lines: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          description: string
          id: string
          item_id: string | null
          line_number: number
          quantity: number
          sdm_id: string
          total_amount: number
          unit_price: number
          uom_id: string | null
          updated_at: string
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          description: string
          id?: string
          item_id?: string | null
          line_number: number
          quantity?: number
          sdm_id: string
          total_amount?: number
          unit_price?: number
          uom_id?: string | null
          updated_at?: string
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          description?: string
          id?: string
          item_id?: string | null
          line_number?: number
          quantity?: number
          sdm_id?: string
          total_amount?: number
          unit_price?: number
          uom_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "supplier_debit_memo_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_debit_memo_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "supplier_debit_memo_lines_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_debit_memo_lines_sdm_id_fkey"
            columns: ["sdm_id"]
            isOneToOne: false
            referencedRelation: "supplier_debit_memos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_debit_memo_lines_sdm_id_fkey"
            columns: ["sdm_id"]
            isOneToOne: false
            referencedRelation: "vw_sdm_register"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_debit_memo_lines_uom_id_fkey"
            columns: ["uom_id"]
            isOneToOne: false
            referencedRelation: "units_of_measure"
            referencedColumns: ["id"]
          },
        ]
      }
      supplier_debit_memos: {
        Row: {
          branch_id: string | null
          company_id: string
          created_at: string
          created_by: string | null
          dm_date: string
          id: string
          reason: string | null
          reference_doc_id: string | null
          reference_doc_type: string | null
          sdm_number: string
          status: string
          supplier_id: string
          supplier_name_snapshot: string
          supplier_tin_snapshot: string | null
          total_amount: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          branch_id?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          dm_date: string
          id?: string
          reason?: string | null
          reference_doc_id?: string | null
          reference_doc_type?: string | null
          sdm_number: string
          status?: string
          supplier_id: string
          supplier_name_snapshot: string
          supplier_tin_snapshot?: string | null
          total_amount?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          branch_id?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          dm_date?: string
          id?: string
          reason?: string | null
          reference_doc_id?: string | null
          reference_doc_type?: string | null
          sdm_number?: string
          status?: string
          supplier_id?: string
          supplier_name_snapshot?: string
          supplier_tin_snapshot?: string | null
          total_amount?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "supplier_debit_memos_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_debit_memos_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_debit_memos_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "supplier_debit_memos_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
      supplier_groups: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          description: string | null
          group_code: string
          group_name: string
          id: string
          is_active: boolean
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          group_code: string
          group_name: string
          id?: string
          is_active?: boolean
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          group_code?: string
          group_name?: string
          id?: string
          is_active?: boolean
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "supplier_groups_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_groups_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      suppliers: {
        Row: {
          business_style: string | null
          company_id: string
          contact_person: string | null
          created_at: string | null
          created_by: string | null
          default_atc_code_id: string | null
          default_currency_id: string | null
          default_gl_account_id: string | null
          default_tax_type: string
          default_terms_id: string | null
          email: string | null
          id: string
          is_active: boolean | null
          is_subject_to_ewt: boolean
          phone_number: string | null
          registered_address: string
          registered_name: string
          supplier_code: string
          supplier_group: string | null
          supplier_group_id: string | null
          tin: string
          trade_name: string | null
          updated_at: string | null
          updated_by: string | null
        }
        Insert: {
          business_style?: string | null
          company_id: string
          contact_person?: string | null
          created_at?: string | null
          created_by?: string | null
          default_atc_code_id?: string | null
          default_currency_id?: string | null
          default_gl_account_id?: string | null
          default_tax_type?: string
          default_terms_id?: string | null
          email?: string | null
          id?: string
          is_active?: boolean | null
          is_subject_to_ewt?: boolean
          phone_number?: string | null
          registered_address: string
          registered_name: string
          supplier_code: string
          supplier_group?: string | null
          supplier_group_id?: string | null
          tin: string
          trade_name?: string | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Update: {
          business_style?: string | null
          company_id?: string
          contact_person?: string | null
          created_at?: string | null
          created_by?: string | null
          default_atc_code_id?: string | null
          default_currency_id?: string | null
          default_gl_account_id?: string | null
          default_tax_type?: string
          default_terms_id?: string | null
          email?: string | null
          id?: string
          is_active?: boolean | null
          is_subject_to_ewt?: boolean
          phone_number?: string | null
          registered_address?: string
          registered_name?: string
          supplier_code?: string
          supplier_group?: string | null
          supplier_group_id?: string | null
          tin?: string
          trade_name?: string | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "suppliers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "suppliers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "suppliers_default_atc_code_id_fkey"
            columns: ["default_atc_code_id"]
            isOneToOne: false
            referencedRelation: "atc_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "suppliers_default_currency_id_fkey"
            columns: ["default_currency_id"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "suppliers_default_gl_account_id_fkey"
            columns: ["default_gl_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "suppliers_default_terms_id_fkey"
            columns: ["default_terms_id"]
            isOneToOne: false
            referencedRelation: "payment_terms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "suppliers_supplier_group_id_fkey"
            columns: ["supplier_group_id"]
            isOneToOne: false
            referencedRelation: "supplier_groups"
            referencedColumns: ["id"]
          },
        ]
      }
      sys_audit_logs: {
        Row: {
          action: string
          changed_at: string | null
          changed_by: string | null
          company_id: string | null
          id: string
          ip_address: string | null
          new_data: Json | null
          old_data: Json | null
          record_id: string | null
          table_name: string
          user_agent: string | null
        }
        Insert: {
          action: string
          changed_at?: string | null
          changed_by?: string | null
          company_id?: string | null
          id?: string
          ip_address?: string | null
          new_data?: Json | null
          old_data?: Json | null
          record_id?: string | null
          table_name: string
          user_agent?: string | null
        }
        Update: {
          action?: string
          changed_at?: string | null
          changed_by?: string | null
          company_id?: string | null
          id?: string
          ip_address?: string | null
          new_data?: Json | null
          old_data?: Json | null
          record_id?: string | null
          table_name?: string
          user_agent?: string | null
        }
        Relationships: []
      }
      sys_feature_enablement: {
        Row: {
          company_id: string
          created_at: string | null
          disabled_at: string | null
          disabled_by: string | null
          enabled_at: string | null
          enabled_by: string | null
          feature_definition_id: string
          id: string
          is_enabled: boolean
          updated_at: string | null
        }
        Insert: {
          company_id: string
          created_at?: string | null
          disabled_at?: string | null
          disabled_by?: string | null
          enabled_at?: string | null
          enabled_by?: string | null
          feature_definition_id: string
          id?: string
          is_enabled?: boolean
          updated_at?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string | null
          disabled_at?: string | null
          disabled_by?: string | null
          enabled_at?: string | null
          enabled_by?: string | null
          feature_definition_id?: string
          id?: string
          is_enabled?: boolean
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sys_feature_enablement_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sys_feature_enablement_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "sys_feature_enablement_feature_definition_id_fkey"
            columns: ["feature_definition_id"]
            isOneToOne: false
            referencedRelation: "ref_feature_definitions"
            referencedColumns: ["id"]
          },
        ]
      }
      sys_posting_guard_violations: {
        Row: {
          company_id: string | null
          current_user_name: string
          id: string
          je_id: string | null
          je_number: string | null
          maintenance_lane: boolean
          observed_at: string
          operation: string
          origin_context: string
          reference_doc_type: string | null
          session_user_name: string
          table_name: string
          writer_function: string | null
        }
        Insert: {
          company_id?: string | null
          current_user_name: string
          id?: string
          je_id?: string | null
          je_number?: string | null
          maintenance_lane?: boolean
          observed_at?: string
          operation: string
          origin_context: string
          reference_doc_type?: string | null
          session_user_name: string
          table_name: string
          writer_function?: string | null
        }
        Update: {
          company_id?: string | null
          current_user_name?: string
          id?: string
          je_id?: string | null
          je_number?: string | null
          maintenance_lane?: boolean
          observed_at?: string
          operation?: string
          origin_context?: string
          reference_doc_type?: string | null
          session_user_name?: string
          table_name?: string
          writer_function?: string | null
        }
        Relationships: []
      }
      tax_calendar_events: {
        Row: {
          assigned_to_user_id: string | null
          company_id: string
          compliance_form_id: string
          coverage_period_end: string
          coverage_period_start: string
          created_at: string | null
          created_by: string | null
          date_filed: string | null
          effective_deadline: string
          efps_adjusted_deadline: string | null
          efps_reference_no: string | null
          id: string
          status: string
          statutory_deadline: string
          updated_at: string | null
          updated_by: string | null
        }
        Insert: {
          assigned_to_user_id?: string | null
          company_id: string
          compliance_form_id: string
          coverage_period_end: string
          coverage_period_start: string
          created_at?: string | null
          created_by?: string | null
          date_filed?: string | null
          effective_deadline: string
          efps_adjusted_deadline?: string | null
          efps_reference_no?: string | null
          id?: string
          status?: string
          statutory_deadline: string
          updated_at?: string | null
          updated_by?: string | null
        }
        Update: {
          assigned_to_user_id?: string | null
          company_id?: string
          compliance_form_id?: string
          coverage_period_end?: string
          coverage_period_start?: string
          created_at?: string | null
          created_by?: string | null
          date_filed?: string | null
          effective_deadline?: string
          efps_adjusted_deadline?: string | null
          efps_reference_no?: string | null
          id?: string
          status?: string
          statutory_deadline?: string
          updated_at?: string | null
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tax_calendar_events_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tax_calendar_events_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "tax_calendar_events_compliance_form_id_fkey"
            columns: ["compliance_form_id"]
            isOneToOne: false
            referencedRelation: "ref_compliance_forms"
            referencedColumns: ["id"]
          },
        ]
      }
      tax_codes: {
        Row: {
          code: string
          created_at: string | null
          created_by: string | null
          deprecated_at: string | null
          deprecated_reason: string | null
          description: string
          effective_from: string
          effective_to: string | null
          gl_account_id: string | null
          id: string
          is_active: boolean | null
          rate: number
          supersedes_tax_code_id: string | null
          tax_type: string
          updated_at: string | null
          updated_by: string | null
        }
        Insert: {
          code: string
          created_at?: string | null
          created_by?: string | null
          deprecated_at?: string | null
          deprecated_reason?: string | null
          description: string
          effective_from?: string
          effective_to?: string | null
          gl_account_id?: string | null
          id?: string
          is_active?: boolean | null
          rate: number
          supersedes_tax_code_id?: string | null
          tax_type: string
          updated_at?: string | null
          updated_by?: string | null
        }
        Update: {
          code?: string
          created_at?: string | null
          created_by?: string | null
          deprecated_at?: string | null
          deprecated_reason?: string | null
          description?: string
          effective_from?: string
          effective_to?: string | null
          gl_account_id?: string | null
          id?: string
          is_active?: boolean | null
          rate?: number
          supersedes_tax_code_id?: string | null
          tax_type?: string
          updated_at?: string | null
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tax_codes_gl_account_id_fkey"
            columns: ["gl_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tax_codes_supersedes_tax_code_id_fkey"
            columns: ["supersedes_tax_code_id"]
            isOneToOne: false
            referencedRelation: "tax_codes"
            referencedColumns: ["id"]
          },
        ]
      }
      tax_credits_schedule: {
        Row: {
          amount: number
          applied_amount: number
          company_id: string
          created_at: string
          created_by: string | null
          credit_type: string
          description: string | null
          id: string
          period_quarter: number | null
          period_year: number
          remarks: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          amount?: number
          applied_amount?: number
          company_id: string
          created_at?: string
          created_by?: string | null
          credit_type: string
          description?: string | null
          id?: string
          period_quarter?: number | null
          period_year: number
          remarks?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          amount?: number
          applied_amount?: number
          company_id?: string
          created_at?: string
          created_by?: string | null
          credit_type?: string
          description?: string | null
          id?: string
          period_quarter?: number | null
          period_year?: number
          remarks?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tax_credits_schedule_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tax_credits_schedule_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      tax_detail_entries: {
        Row: {
          atc_code_id: string | null
          branch_id: string | null
          company_id: string
          counterparty_id: string | null
          counterparty_name: string | null
          counterparty_tin: string | null
          created_at: string
          document_date: string
          filing_status: string
          id: string
          income_nature: string | null
          is_reversal: boolean
          percentage_tax_code_id: string | null
          posting_date: string
          reverses_tax_detail_id: string | null
          source_doc_id: string
          source_doc_type: string
          source_line_id: string | null
          tax_amount: number
          tax_base: number
          tax_code_id: string | null
          tax_kind: string
          tax_period_id: string | null
          tax_rate: number | null
          vat_code_id: string | null
        }
        Insert: {
          atc_code_id?: string | null
          branch_id?: string | null
          company_id: string
          counterparty_id?: string | null
          counterparty_name?: string | null
          counterparty_tin?: string | null
          created_at?: string
          document_date: string
          filing_status?: string
          id?: string
          income_nature?: string | null
          is_reversal?: boolean
          percentage_tax_code_id?: string | null
          posting_date: string
          reverses_tax_detail_id?: string | null
          source_doc_id: string
          source_doc_type: string
          source_line_id?: string | null
          tax_amount?: number
          tax_base?: number
          tax_code_id?: string | null
          tax_kind: string
          tax_period_id?: string | null
          tax_rate?: number | null
          vat_code_id?: string | null
        }
        Update: {
          atc_code_id?: string | null
          branch_id?: string | null
          company_id?: string
          counterparty_id?: string | null
          counterparty_name?: string | null
          counterparty_tin?: string | null
          created_at?: string
          document_date?: string
          filing_status?: string
          id?: string
          income_nature?: string | null
          is_reversal?: boolean
          percentage_tax_code_id?: string | null
          posting_date?: string
          reverses_tax_detail_id?: string | null
          source_doc_id?: string
          source_doc_type?: string
          source_line_id?: string | null
          tax_amount?: number
          tax_base?: number
          tax_code_id?: string | null
          tax_kind?: string
          tax_period_id?: string | null
          tax_rate?: number | null
          vat_code_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tax_detail_entries_atc_code_id_fkey"
            columns: ["atc_code_id"]
            isOneToOne: false
            referencedRelation: "atc_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tax_detail_entries_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tax_detail_entries_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tax_detail_entries_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "tax_detail_entries_percentage_tax_code_id_fkey"
            columns: ["percentage_tax_code_id"]
            isOneToOne: false
            referencedRelation: "percentage_tax_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tax_detail_entries_reverses_tax_detail_id_fkey"
            columns: ["reverses_tax_detail_id"]
            isOneToOne: false
            referencedRelation: "tax_detail_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tax_detail_entries_tax_code_id_fkey"
            columns: ["tax_code_id"]
            isOneToOne: false
            referencedRelation: "tax_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tax_detail_entries_tax_period_id_fkey"
            columns: ["tax_period_id"]
            isOneToOne: false
            referencedRelation: "fiscal_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tax_detail_entries_vat_code_id_fkey"
            columns: ["vat_code_id"]
            isOneToOne: false
            referencedRelation: "vat_codes"
            referencedColumns: ["id"]
          },
        ]
      }
      transaction_events: {
        Row: {
          actor_id: string | null
          actor_role: string | null
          after_status: string | null
          before_status: string | null
          company_id: string
          created_at: string
          details: Json
          event_type: string
          id: string
          journal_entry_id: string | null
          occurred_at: string
          reason: string | null
          source_doc_id: string | null
          source_doc_type: string
          source_document_no: string | null
          source_table: string | null
        }
        Insert: {
          actor_id?: string | null
          actor_role?: string | null
          after_status?: string | null
          before_status?: string | null
          company_id: string
          created_at?: string
          details?: Json
          event_type: string
          id?: string
          journal_entry_id?: string | null
          occurred_at?: string
          reason?: string | null
          source_doc_id?: string | null
          source_doc_type: string
          source_document_no?: string | null
          source_table?: string | null
        }
        Update: {
          actor_id?: string | null
          actor_role?: string | null
          after_status?: string | null
          before_status?: string | null
          company_id?: string
          created_at?: string
          details?: Json
          event_type?: string
          id?: string
          journal_entry_id?: string | null
          occurred_at?: string
          reason?: string | null
          source_doc_id?: string | null
          source_doc_type?: string
          source_document_no?: string | null
          source_table?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "transaction_events_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transaction_events_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "transaction_events_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
        ]
      }
      units_of_measure: {
        Row: {
          base_uom_id: string | null
          company_id: string
          conversion_factor: number | null
          created_at: string | null
          created_by: string | null
          description: string
          id: string
          is_active: boolean | null
          is_base_unit: boolean
          uom_code: string
          updated_at: string | null
          updated_by: string | null
        }
        Insert: {
          base_uom_id?: string | null
          company_id: string
          conversion_factor?: number | null
          created_at?: string | null
          created_by?: string | null
          description: string
          id?: string
          is_active?: boolean | null
          is_base_unit?: boolean
          uom_code: string
          updated_at?: string | null
          updated_by?: string | null
        }
        Update: {
          base_uom_id?: string | null
          company_id?: string
          conversion_factor?: number | null
          created_at?: string | null
          created_by?: string | null
          description?: string
          id?: string
          is_active?: boolean | null
          is_base_unit?: boolean
          uom_code?: string
          updated_at?: string | null
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "units_of_measure_base_uom_id_fkey"
            columns: ["base_uom_id"]
            isOneToOne: false
            referencedRelation: "units_of_measure"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "units_of_measure_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "units_of_measure_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      user_company_branch_scopes: {
        Row: {
          branch_id: string
          company_id: string
          granted_at: string
          granted_by: string | null
          id: string
          is_active: boolean
          updated_at: string
          user_id: string
        }
        Insert: {
          branch_id: string
          company_id: string
          granted_at?: string
          granted_by?: string | null
          id?: string
          is_active?: boolean
          updated_at?: string
          user_id: string
        }
        Update: {
          branch_id?: string
          company_id?: string
          granted_at?: string
          granted_by?: string | null
          id?: string
          is_active?: boolean
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_company_branch_scopes_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_company_branch_scopes_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_company_branch_scopes_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      user_company_memberships: {
        Row: {
          company_id: string
          granted_at: string
          granted_by: string | null
          id: string
          role: string
          user_id: string
        }
        Insert: {
          company_id: string
          granted_at?: string
          granted_by?: string | null
          id?: string
          role?: string
          user_id: string
        }
        Update: {
          company_id?: string
          granted_at?: string
          granted_by?: string | null
          id?: string
          role?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_company_memberships_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_company_memberships_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      vat_codes: {
        Row: {
          created_at: string | null
          deprecated_at: string | null
          deprecated_reason: string | null
          description: string
          effective_from: string
          effective_to: string | null
          id: string
          is_active: boolean | null
          relief_category: string | null
          supersedes_vat_code_id: string | null
          tax_code_id: string
          transaction_type: string
          vat_classification: string
          vat_code: string
        }
        Insert: {
          created_at?: string | null
          deprecated_at?: string | null
          deprecated_reason?: string | null
          description: string
          effective_from?: string
          effective_to?: string | null
          id?: string
          is_active?: boolean | null
          relief_category?: string | null
          supersedes_vat_code_id?: string | null
          tax_code_id: string
          transaction_type: string
          vat_classification: string
          vat_code: string
        }
        Update: {
          created_at?: string | null
          deprecated_at?: string | null
          deprecated_reason?: string | null
          description?: string
          effective_from?: string
          effective_to?: string | null
          id?: string
          is_active?: boolean | null
          relief_category?: string | null
          supersedes_vat_code_id?: string | null
          tax_code_id?: string
          transaction_type?: string
          vat_classification?: string
          vat_code?: string
        }
        Relationships: [
          {
            foreignKeyName: "vat_codes_supersedes_vat_code_id_fkey"
            columns: ["supersedes_vat_code_id"]
            isOneToOne: false
            referencedRelation: "vat_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vat_codes_tax_code_id_fkey"
            columns: ["tax_code_id"]
            isOneToOne: false
            referencedRelation: "tax_codes"
            referencedColumns: ["id"]
          },
        ]
      }
      vat_returns: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          exempt_sales: number
          filed_date: string | null
          id: string
          input_taxable_purchases: number
          input_vat: number
          input_vat_carried_over: number
          net_vat_payable: number
          output_taxable_sales: number
          output_vat: number
          period_month: number | null
          period_quarter: number | null
          period_year: number
          reference_no: string | null
          remarks: string | null
          return_type: string
          status: string
          total_available_input_vat: number
          updated_at: string
          updated_by: string | null
          vat_paid_prior_months: number
          vat_still_due: number
          zero_rated_sales: number
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          exempt_sales?: number
          filed_date?: string | null
          id?: string
          input_taxable_purchases?: number
          input_vat?: number
          input_vat_carried_over?: number
          net_vat_payable?: number
          output_taxable_sales?: number
          output_vat?: number
          period_month?: number | null
          period_quarter?: number | null
          period_year: number
          reference_no?: string | null
          remarks?: string | null
          return_type: string
          status?: string
          total_available_input_vat?: number
          updated_at?: string
          updated_by?: string | null
          vat_paid_prior_months?: number
          vat_still_due?: number
          zero_rated_sales?: number
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          exempt_sales?: number
          filed_date?: string | null
          id?: string
          input_taxable_purchases?: number
          input_vat?: number
          input_vat_carried_over?: number
          net_vat_payable?: number
          output_taxable_sales?: number
          output_vat?: number
          period_month?: number | null
          period_quarter?: number | null
          period_year?: number
          reference_no?: string | null
          remarks?: string | null
          return_type?: string
          status?: string
          total_available_input_vat?: number
          updated_at?: string
          updated_by?: string | null
          vat_paid_prior_months?: number
          vat_still_due?: number
          zero_rated_sales?: number
        }
        Relationships: [
          {
            foreignKeyName: "vat_returns_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vat_returns_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      vendor_bill_lines: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          description: string
          discount_amount: number
          discount_percent: number
          ewt_amount: number
          ewt_atc_code_id: string | null
          ewt_income_nature: string | null
          ewt_tax_base: number | null
          ewt_variance_reason: string | null
          expense_account_id: string | null
          id: string
          input_vat_amount: number
          item_id: string | null
          line_number: number
          net_amount: number
          quantity: number
          total_amount: number
          unit_price: number
          uom_id: string | null
          updated_at: string
          updated_by: string | null
          vat_code_id: string | null
          vendor_bill_id: string
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          description: string
          discount_amount?: number
          discount_percent?: number
          ewt_amount?: number
          ewt_atc_code_id?: string | null
          ewt_income_nature?: string | null
          ewt_tax_base?: number | null
          ewt_variance_reason?: string | null
          expense_account_id?: string | null
          id?: string
          input_vat_amount?: number
          item_id?: string | null
          line_number: number
          net_amount?: number
          quantity?: number
          total_amount?: number
          unit_price?: number
          uom_id?: string | null
          updated_at?: string
          updated_by?: string | null
          vat_code_id?: string | null
          vendor_bill_id: string
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          description?: string
          discount_amount?: number
          discount_percent?: number
          ewt_amount?: number
          ewt_atc_code_id?: string | null
          ewt_income_nature?: string | null
          ewt_tax_base?: number | null
          ewt_variance_reason?: string | null
          expense_account_id?: string | null
          id?: string
          input_vat_amount?: number
          item_id?: string | null
          line_number?: number
          net_amount?: number
          quantity?: number
          total_amount?: number
          unit_price?: number
          uom_id?: string | null
          updated_at?: string
          updated_by?: string | null
          vat_code_id?: string | null
          vendor_bill_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vendor_bill_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_bill_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "vendor_bill_lines_ewt_atc_code_id_fkey"
            columns: ["ewt_atc_code_id"]
            isOneToOne: false
            referencedRelation: "atc_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_bill_lines_expense_account_id_fkey"
            columns: ["expense_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_bill_lines_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_bill_lines_uom_id_fkey"
            columns: ["uom_id"]
            isOneToOne: false
            referencedRelation: "units_of_measure"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_bill_lines_vat_code_id_fkey"
            columns: ["vat_code_id"]
            isOneToOne: false
            referencedRelation: "vat_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_bill_lines_vendor_bill_id_fkey"
            columns: ["vendor_bill_id"]
            isOneToOne: false
            referencedRelation: "vendor_bills"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_bill_lines_vendor_bill_id_fkey"
            columns: ["vendor_bill_id"]
            isOneToOne: false
            referencedRelation: "vw_ap_aging"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_bill_lines_vendor_bill_id_fkey"
            columns: ["vendor_bill_id"]
            isOneToOne: false
            referencedRelation: "vw_vendor_bill_register"
            referencedColumns: ["id"]
          },
        ]
      }
      vendor_bills: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          bill_date: string
          bill_number: string
          branch_id: string | null
          company_id: string
          cost_center_id: string | null
          created_at: string
          created_by: string | null
          currency_code: string
          department_id: string | null
          due_date: string | null
          ewt_amount_expected: number | null
          fiscal_period_id: string | null
          functional_entity_id: string | null
          id: string
          journal_entry_id: string | null
          location_id: string | null
          memo: string | null
          payment_terms_id: string | null
          posted_at: string | null
          posted_by: string | null
          project_id: string | null
          reference: string | null
          rr_id: string | null
          status: string
          supplier_id: string
          supplier_invoice_number: string | null
          supplier_name_snapshot: string
          supplier_tin_snapshot: string | null
          total_amount: number
          total_exempt_amount: number
          total_input_vat_amount: number
          total_taxable_amount: number
          total_zero_rated_amount: number
          updated_at: string
          updated_by: string | null
          void_reason_id: string | null
          warehouse_id: string | null
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          bill_date: string
          bill_number: string
          branch_id?: string | null
          company_id: string
          cost_center_id?: string | null
          created_at?: string
          created_by?: string | null
          currency_code?: string
          department_id?: string | null
          due_date?: string | null
          ewt_amount_expected?: number | null
          fiscal_period_id?: string | null
          functional_entity_id?: string | null
          id?: string
          journal_entry_id?: string | null
          location_id?: string | null
          memo?: string | null
          payment_terms_id?: string | null
          posted_at?: string | null
          posted_by?: string | null
          project_id?: string | null
          reference?: string | null
          rr_id?: string | null
          status?: string
          supplier_id: string
          supplier_invoice_number?: string | null
          supplier_name_snapshot: string
          supplier_tin_snapshot?: string | null
          total_amount?: number
          total_exempt_amount?: number
          total_input_vat_amount?: number
          total_taxable_amount?: number
          total_zero_rated_amount?: number
          updated_at?: string
          updated_by?: string | null
          void_reason_id?: string | null
          warehouse_id?: string | null
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          bill_date?: string
          bill_number?: string
          branch_id?: string | null
          company_id?: string
          cost_center_id?: string | null
          created_at?: string
          created_by?: string | null
          currency_code?: string
          department_id?: string | null
          due_date?: string | null
          ewt_amount_expected?: number | null
          fiscal_period_id?: string | null
          functional_entity_id?: string | null
          id?: string
          journal_entry_id?: string | null
          location_id?: string | null
          memo?: string | null
          payment_terms_id?: string | null
          posted_at?: string | null
          posted_by?: string | null
          project_id?: string | null
          reference?: string | null
          rr_id?: string | null
          status?: string
          supplier_id?: string
          supplier_invoice_number?: string | null
          supplier_name_snapshot?: string
          supplier_tin_snapshot?: string | null
          total_amount?: number
          total_exempt_amount?: number
          total_input_vat_amount?: number
          total_taxable_amount?: number
          total_zero_rated_amount?: number
          updated_at?: string
          updated_by?: string | null
          void_reason_id?: string | null
          warehouse_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "vendor_bills_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_bills_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_bills_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "vendor_bills_cost_center_id_fkey"
            columns: ["cost_center_id"]
            isOneToOne: false
            referencedRelation: "cost_centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_bills_department_id_fkey"
            columns: ["department_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_bills_fiscal_period_id_fkey"
            columns: ["fiscal_period_id"]
            isOneToOne: false
            referencedRelation: "fiscal_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_bills_functional_entity_id_fkey"
            columns: ["functional_entity_id"]
            isOneToOne: false
            referencedRelation: "functional_entities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_bills_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_bills_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_bills_payment_terms_id_fkey"
            columns: ["payment_terms_id"]
            isOneToOne: false
            referencedRelation: "payment_terms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_bills_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_bills_rr_id_fkey"
            columns: ["rr_id"]
            isOneToOne: false
            referencedRelation: "receiving_reports"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_bills_rr_id_fkey"
            columns: ["rr_id"]
            isOneToOne: false
            referencedRelation: "vw_rr_item_billing_progress"
            referencedColumns: ["rr_id"]
          },
          {
            foreignKeyName: "vendor_bills_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_bills_void_reason_id_fkey"
            columns: ["void_reason_id"]
            isOneToOne: false
            referencedRelation: "void_reason_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_bills_warehouse_id_fkey"
            columns: ["warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
        ]
      }
      vendor_credit_applications: {
        Row: {
          applied_amount: number
          applied_by: string | null
          applied_date: string
          company_id: string
          created_at: string
          id: string
          remarks: string | null
          reversal_reason: string | null
          reversed_at: string | null
          reversed_by: string | null
          reversed_date: string | null
          vendor_bill_id: string
          vendor_credit_id: string
        }
        Insert: {
          applied_amount: number
          applied_by?: string | null
          applied_date: string
          company_id: string
          created_at?: string
          id?: string
          remarks?: string | null
          reversal_reason?: string | null
          reversed_at?: string | null
          reversed_by?: string | null
          reversed_date?: string | null
          vendor_bill_id: string
          vendor_credit_id: string
        }
        Update: {
          applied_amount?: number
          applied_by?: string | null
          applied_date?: string
          company_id?: string
          created_at?: string
          id?: string
          remarks?: string | null
          reversal_reason?: string | null
          reversed_at?: string | null
          reversed_by?: string | null
          reversed_date?: string | null
          vendor_bill_id?: string
          vendor_credit_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vendor_credit_applications_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_credit_applications_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "vendor_credit_applications_vendor_bill_id_fkey"
            columns: ["vendor_bill_id"]
            isOneToOne: false
            referencedRelation: "vendor_bills"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_credit_applications_vendor_bill_id_fkey"
            columns: ["vendor_bill_id"]
            isOneToOne: false
            referencedRelation: "vw_ap_aging"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_credit_applications_vendor_bill_id_fkey"
            columns: ["vendor_bill_id"]
            isOneToOne: false
            referencedRelation: "vw_vendor_bill_register"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_credit_applications_vendor_credit_id_fkey"
            columns: ["vendor_credit_id"]
            isOneToOne: false
            referencedRelation: "vendor_credits"
            referencedColumns: ["id"]
          },
        ]
      }
      vendor_credit_lines: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          description: string
          expense_account_id: string | null
          id: string
          input_vat_amount: number
          item_id: string | null
          line_number: number
          net_amount: number
          quantity: number
          total_amount: number
          unit_price: number
          uom_id: string | null
          updated_at: string
          updated_by: string | null
          vat_code_id: string | null
          vc_id: string
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          description: string
          expense_account_id?: string | null
          id?: string
          input_vat_amount?: number
          item_id?: string | null
          line_number: number
          net_amount?: number
          quantity?: number
          total_amount?: number
          unit_price?: number
          uom_id?: string | null
          updated_at?: string
          updated_by?: string | null
          vat_code_id?: string | null
          vc_id: string
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          description?: string
          expense_account_id?: string | null
          id?: string
          input_vat_amount?: number
          item_id?: string | null
          line_number?: number
          net_amount?: number
          quantity?: number
          total_amount?: number
          unit_price?: number
          uom_id?: string | null
          updated_at?: string
          updated_by?: string | null
          vat_code_id?: string | null
          vc_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vendor_credit_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_credit_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "vendor_credit_lines_expense_account_id_fkey"
            columns: ["expense_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_credit_lines_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_credit_lines_uom_id_fkey"
            columns: ["uom_id"]
            isOneToOne: false
            referencedRelation: "units_of_measure"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_credit_lines_vat_code_id_fkey"
            columns: ["vat_code_id"]
            isOneToOne: false
            referencedRelation: "vat_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_credit_lines_vc_id_fkey"
            columns: ["vc_id"]
            isOneToOne: false
            referencedRelation: "vendor_credits"
            referencedColumns: ["id"]
          },
        ]
      }
      vendor_credits: {
        Row: {
          branch_id: string | null
          company_id: string
          created_at: string
          created_by: string | null
          credit_date: string
          fiscal_period_id: string | null
          id: string
          journal_entry_id: string | null
          posted_at: string | null
          posted_by: string | null
          reference_bill_id: string | null
          remaining_balance: number
          remarks: string | null
          status: string
          supplier_cm_no: string | null
          supplier_id: string
          supplier_name_snapshot: string
          supplier_tin_snapshot: string | null
          total_amount: number
          total_input_vat_amount: number
          total_taxable_amount: number
          updated_at: string
          updated_by: string | null
          vc_number: string
        }
        Insert: {
          branch_id?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          credit_date: string
          fiscal_period_id?: string | null
          id?: string
          journal_entry_id?: string | null
          posted_at?: string | null
          posted_by?: string | null
          reference_bill_id?: string | null
          remaining_balance?: number
          remarks?: string | null
          status?: string
          supplier_cm_no?: string | null
          supplier_id: string
          supplier_name_snapshot: string
          supplier_tin_snapshot?: string | null
          total_amount?: number
          total_input_vat_amount?: number
          total_taxable_amount?: number
          updated_at?: string
          updated_by?: string | null
          vc_number: string
        }
        Update: {
          branch_id?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          credit_date?: string
          fiscal_period_id?: string | null
          id?: string
          journal_entry_id?: string | null
          posted_at?: string | null
          posted_by?: string | null
          reference_bill_id?: string | null
          remaining_balance?: number
          remarks?: string | null
          status?: string
          supplier_cm_no?: string | null
          supplier_id?: string
          supplier_name_snapshot?: string
          supplier_tin_snapshot?: string | null
          total_amount?: number
          total_input_vat_amount?: number
          total_taxable_amount?: number
          updated_at?: string
          updated_by?: string | null
          vc_number?: string
        }
        Relationships: [
          {
            foreignKeyName: "vendor_credits_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_credits_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_credits_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "vendor_credits_fiscal_period_id_fkey"
            columns: ["fiscal_period_id"]
            isOneToOne: false
            referencedRelation: "fiscal_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_credits_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_credits_reference_bill_id_fkey"
            columns: ["reference_bill_id"]
            isOneToOne: false
            referencedRelation: "vendor_bills"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_credits_reference_bill_id_fkey"
            columns: ["reference_bill_id"]
            isOneToOne: false
            referencedRelation: "vw_ap_aging"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_credits_reference_bill_id_fkey"
            columns: ["reference_bill_id"]
            isOneToOne: false
            referencedRelation: "vw_vendor_bill_register"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_credits_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
      void_reason_codes: {
        Row: {
          code: string
          created_at: string
          description: string
          id: string
          is_active: boolean
        }
        Insert: {
          code: string
          created_at?: string
          description: string
          id?: string
          is_active?: boolean
        }
        Update: {
          code?: string
          created_at?: string
          description?: string
          id?: string
          is_active?: boolean
        }
        Relationships: []
      }
      warehouse_item_settings: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          id: string
          item_id: string
          lead_time_days: number | null
          max_stock_level: number | null
          min_stock_level: number
          notes: string | null
          preferred_supplier_id: string | null
          reorder_point: number | null
          reorder_qty: number | null
          updated_at: string
          updated_by: string | null
          warehouse_id: string
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          id?: string
          item_id: string
          lead_time_days?: number | null
          max_stock_level?: number | null
          min_stock_level?: number
          notes?: string | null
          preferred_supplier_id?: string | null
          reorder_point?: number | null
          reorder_qty?: number | null
          updated_at?: string
          updated_by?: string | null
          warehouse_id: string
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          id?: string
          item_id?: string
          lead_time_days?: number | null
          max_stock_level?: number | null
          min_stock_level?: number
          notes?: string | null
          preferred_supplier_id?: string | null
          reorder_point?: number | null
          reorder_qty?: number | null
          updated_at?: string
          updated_by?: string | null
          warehouse_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "warehouse_item_settings_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "warehouse_item_settings_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "warehouse_item_settings_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "warehouse_item_settings_preferred_supplier_id_fkey"
            columns: ["preferred_supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "warehouse_item_settings_warehouse_id_fkey"
            columns: ["warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
        ]
      }
      warehouse_zones: {
        Row: {
          created_at: string
          id: string
          is_active: boolean
          warehouse_id: string
          zone_code: string
          zone_name: string
        }
        Insert: {
          created_at?: string
          id?: string
          is_active?: boolean
          warehouse_id: string
          zone_code: string
          zone_name: string
        }
        Update: {
          created_at?: string
          id?: string
          is_active?: boolean
          warehouse_id?: string
          zone_code?: string
          zone_name?: string
        }
        Relationships: [
          {
            foreignKeyName: "warehouse_zones_warehouse_id_fkey"
            columns: ["warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
        ]
      }
      warehouses: {
        Row: {
          address: string | null
          branch_id: string | null
          company_id: string
          created_at: string
          created_by: string | null
          gl_inventory_account_id: string | null
          gl_variance_account_id: string | null
          id: string
          is_active: boolean
          updated_at: string
          updated_by: string | null
          warehouse_code: string
          warehouse_name: string
          warehouse_type: string
        }
        Insert: {
          address?: string | null
          branch_id?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          gl_inventory_account_id?: string | null
          gl_variance_account_id?: string | null
          id?: string
          is_active?: boolean
          updated_at?: string
          updated_by?: string | null
          warehouse_code: string
          warehouse_name: string
          warehouse_type?: string
        }
        Update: {
          address?: string | null
          branch_id?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          gl_inventory_account_id?: string | null
          gl_variance_account_id?: string | null
          id?: string
          is_active?: boolean
          updated_at?: string
          updated_by?: string | null
          warehouse_code?: string
          warehouse_name?: string
          warehouse_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "warehouses_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "warehouses_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "warehouses_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "warehouses_gl_inventory_account_id_fkey"
            columns: ["gl_inventory_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "warehouses_gl_variance_account_id_fkey"
            columns: ["gl_variance_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      withholding_remittances: {
        Row: {
          amount: number
          branch_id: string | null
          company_id: string
          created_at: string
          created_by: string | null
          fiscal_period_id: string | null
          form_type: string | null
          id: string
          journal_entry_id: string | null
          particulars: string | null
          period_month: number | null
          period_quarter: number | null
          period_year: number
          posted_at: string | null
          posted_by: string | null
          reference_no: string | null
          remittance_date: string
          remittance_kind: string
          remittance_number: string
          settlement_account_id: string
          status: string
          updated_at: string
          updated_by: string | null
          void_reason: string | null
          voided_at: string | null
          voided_by: string | null
        }
        Insert: {
          amount: number
          branch_id?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          fiscal_period_id?: string | null
          form_type?: string | null
          id?: string
          journal_entry_id?: string | null
          particulars?: string | null
          period_month?: number | null
          period_quarter?: number | null
          period_year: number
          posted_at?: string | null
          posted_by?: string | null
          reference_no?: string | null
          remittance_date: string
          remittance_kind: string
          remittance_number: string
          settlement_account_id: string
          status?: string
          updated_at?: string
          updated_by?: string | null
          void_reason?: string | null
          voided_at?: string | null
          voided_by?: string | null
        }
        Update: {
          amount?: number
          branch_id?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          fiscal_period_id?: string | null
          form_type?: string | null
          id?: string
          journal_entry_id?: string | null
          particulars?: string | null
          period_month?: number | null
          period_quarter?: number | null
          period_year?: number
          posted_at?: string | null
          posted_by?: string | null
          reference_no?: string | null
          remittance_date?: string
          remittance_kind?: string
          remittance_number?: string
          settlement_account_id?: string
          status?: string
          updated_at?: string
          updated_by?: string | null
          void_reason?: string | null
          voided_at?: string | null
          voided_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "withholding_remittances_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "withholding_remittances_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "withholding_remittances_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "withholding_remittances_fiscal_period_id_fkey"
            columns: ["fiscal_period_id"]
            isOneToOne: false
            referencedRelation: "fiscal_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "withholding_remittances_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "withholding_remittances_settlement_account_id_fkey"
            columns: ["settlement_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      vw_ap_aging: {
        Row: {
          balance_due: number | null
          bill_date: string | null
          bill_number: string | null
          company_id: string | null
          due_date: string | null
          id: string | null
          supplier_id: string | null
          supplier_name: string | null
          supplier_tin: string | null
          total_amount: number | null
        }
        Relationships: [
          {
            foreignKeyName: "vendor_bills_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_bills_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "vendor_bills_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
      vw_available_inventory_identities: {
        Row: {
          available_qty: number | null
          company_id: string | null
          inventory_cost_layer_id: string | null
          item_id: string | null
          layer_date: string | null
          lot_number: string | null
          origin_inventory_transaction_id: string | null
          reference_doc_id: string | null
          reference_doc_type: string | null
          remaining_value: number | null
          serial_number: string | null
          source_line_id: string | null
          unit_cost: number | null
          warehouse_id: string | null
        }
        Relationships: [
          {
            foreignKeyName: "inventory_cost_layers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_cost_layers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "inventory_cost_layers_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_cost_layers_origin_inventory_transaction_id_fkey"
            columns: ["origin_inventory_transaction_id"]
            isOneToOne: false
            referencedRelation: "inventory_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_cost_layers_warehouse_id_fkey"
            columns: ["warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
        ]
      }
      vw_cas_atp_usage: {
        Row: {
          at_or_below_alert_threshold: boolean | null
          atp_alert_threshold: number | null
          atp_series_end: number | null
          atp_series_start: number | null
          branch_id: string | null
          branch_name: string | null
          company_id: string | null
          current_sequence: number | null
          document_code: string | null
          document_name: string | null
          is_active: boolean | null
          is_exhausted: boolean | null
          issued_count: number | null
          next_sequence: number | null
          number_series_id: string | null
          numbers_remaining: number | null
          padding: number | null
          prefix: string | null
          reserved_count: number | null
          suffix: string | null
          total_allocated_count: number | null
          usage_percent: number | null
          voided_count: number | null
        }
        Relationships: [
          {
            foreignKeyName: "number_series_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "number_series_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "number_series_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      vw_company_accounting_config: {
        Row: {
          ap_account_id: string | null
          ar_account_id: string | null
          company_id: string | null
          customer_advances_account_id: string | null
          default_cash_account_id: string | null
          ewt_payable_account_id: string | null
          ewt_withheld_account_id: string | null
          input_vat_account_id: string | null
          supplier_down_payments_account_id: string | null
          vat_payable_account_id: string | null
        }
        Relationships: []
      }
      vw_credit_memo_register: {
        Row: {
          branch_id: string | null
          cm_date: string | null
          cm_id: string | null
          cm_number: string | null
          company_id: string | null
          customer_name_snapshot: string | null
          customer_tin_snapshot: string | null
          reason_description: string | null
          remarks: string | null
          status: string | null
          total_amount: number | null
          total_net_amount: number | null
          total_vat_amount: number | null
        }
        Relationships: [
          {
            foreignKeyName: "credit_memos_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "credit_memos_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "credit_memos_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      vw_customer_ledger: {
        Row: {
          company_id: string | null
          created_at: string | null
          credit_amount: number | null
          customer_id: string | null
          debit_amount: number | null
          description: string | null
          doc_number: string | null
          doc_type: string | null
          source_doc_id: string | null
          source_doc_type: string | null
          transaction_date: string | null
        }
        Relationships: []
      }
      vw_cwt_summary_ar: {
        Row: {
          atc_code: string | null
          atc_code_id: string | null
          company_id: string | null
          customer_id: string | null
          customer_name: string | null
          customer_tin: string | null
          cwt_withheld: number | null
          income_payment: number | null
          nature_of_income: string | null
          receipt_date: string | null
          source_doc_id: string | null
          source_doc_type: string | null
          tax_rate: number | null
          transaction_id: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tax_detail_entries_atc_code_id_fkey"
            columns: ["atc_code_id"]
            isOneToOne: false
            referencedRelation: "atc_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tax_detail_entries_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tax_detail_entries_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      vw_debit_memo_register: {
        Row: {
          branch_id: string | null
          company_id: string | null
          customer_name_snapshot: string | null
          customer_tin_snapshot: string | null
          dm_date: string | null
          dm_id: string | null
          dm_number: string | null
          reason_description: string | null
          remarks: string | null
          status: string | null
          total_amount: number | null
          total_net_amount: number | null
          total_vat_amount: number | null
        }
        Relationships: [
          {
            foreignKeyName: "debit_memos_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "debit_memos_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "debit_memos_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      vw_deposits_in_transit: {
        Row: {
          account_number: string | null
          amount: number | null
          bank_account_id: string | null
          bank_name: string | null
          company_id: string | null
          description: string | null
          document_date: string | null
          id: string | null
          recon_month: number | null
          recon_year: number | null
          reconciliation_id: string | null
          reference_doc_type: string | null
        }
        Relationships: [
          {
            foreignKeyName: "bank_recon_items_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_recon_items_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "bank_recon_items_reconciliation_id_fkey"
            columns: ["reconciliation_id"]
            isOneToOne: false
            referencedRelation: "bank_reconciliations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_reconciliations_bank_account_id_fkey"
            columns: ["bank_account_id"]
            isOneToOne: false
            referencedRelation: "bank_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      vw_ewt_summary_ap: {
        Row: {
          atc_code: string | null
          atc_code_id: string | null
          company_id: string | null
          invoice_date: string | null
          nature_of_payment: string | null
          source_doc_id: string | null
          source_doc_type: string | null
          supplier_id: string | null
          supplier_name: string | null
          supplier_tin: string | null
          tax_base: number | null
          tax_rate: number | null
          tax_withheld: number | null
          transaction_id: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tax_detail_entries_atc_code_id_fkey"
            columns: ["atc_code_id"]
            isOneToOne: false
            referencedRelation: "atc_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tax_detail_entries_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tax_detail_entries_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      vw_general_ledger: {
        Row: {
          account_code: string | null
          account_id: string | null
          account_name: string | null
          account_type: string | null
          branch_id: string | null
          company_id: string | null
          cost_center_id: string | null
          credit_amount: number | null
          debit_amount: number | null
          department_id: string | null
          entry_class: string | null
          fiscal_period_id: string | null
          functional_entity_id: string | null
          is_auto_reversal: boolean | null
          je_date: string | null
          je_description: string | null
          je_id: string | null
          je_number: string | null
          je_status: string | null
          line_description: string | null
          line_id: string | null
          line_number: number | null
          location_id: string | null
          normal_balance: string | null
          period_end: string | null
          period_name: string | null
          period_start: string | null
          project_id: string | null
          reference_doc_id: string | null
          reference_doc_type: string | null
          reversed_by_je_id: string | null
        }
        Relationships: [
          {
            foreignKeyName: "journal_entries_fiscal_period_id_fkey"
            columns: ["fiscal_period_id"]
            isOneToOne: false
            referencedRelation: "fiscal_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entries_reference_doc_type_fkey"
            columns: ["reference_doc_type"]
            isOneToOne: false
            referencedRelation: "ref_posting_source_types"
            referencedColumns: ["document_type"]
          },
          {
            foreignKeyName: "journal_entries_reversed_by_je_id_fkey"
            columns: ["reversed_by_je_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entry_lines_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entry_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entry_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "journal_entry_lines_cost_center_id_fkey"
            columns: ["cost_center_id"]
            isOneToOne: false
            referencedRelation: "cost_centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entry_lines_department_id_fkey"
            columns: ["department_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entry_lines_functional_entity_id_fkey"
            columns: ["functional_entity_id"]
            isOneToOne: false
            referencedRelation: "functional_entities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entry_lines_je_id_fkey"
            columns: ["je_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entry_lines_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entry_lines_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
        ]
      }
      vw_gl_dimension_summary: {
        Row: {
          account_code: string | null
          account_id: string | null
          account_name: string | null
          account_type: string | null
          branch_id: string | null
          company_id: string | null
          cost_center_id: string | null
          department_id: string | null
          fiscal_period_id: string | null
          functional_entity_id: string | null
          line_count: number | null
          location_id: string | null
          net_debit: number | null
          period_name: string | null
          project_id: string | null
          total_credit: number | null
          total_debit: number | null
        }
        Relationships: [
          {
            foreignKeyName: "journal_entries_fiscal_period_id_fkey"
            columns: ["fiscal_period_id"]
            isOneToOne: false
            referencedRelation: "fiscal_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entry_lines_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entry_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entry_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "journal_entry_lines_cost_center_id_fkey"
            columns: ["cost_center_id"]
            isOneToOne: false
            referencedRelation: "cost_centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entry_lines_department_id_fkey"
            columns: ["department_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entry_lines_functional_entity_id_fkey"
            columns: ["functional_entity_id"]
            isOneToOne: false
            referencedRelation: "functional_entities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entry_lines_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entry_lines_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
        ]
      }
      vw_input_vat_review: {
        Row: {
          company_id: string | null
          exempt_purchases: number | null
          gross_purchases: number | null
          input_vat: number | null
          invoice_date: string | null
          invoice_no: string | null
          source_doc_id: string | null
          source_doc_type: string | null
          source_module: string | null
          supplier_address: string | null
          supplier_name: string | null
          supplier_tin: string | null
          system_no: string | null
          taxable_base: number | null
          transaction_id: string | null
          zero_rated: number | null
        }
        Relationships: [
          {
            foreignKeyName: "tax_detail_entries_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tax_detail_entries_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      vw_inventory_valuation_reconciliation: {
        Row: {
          active_layer_qty: number | null
          active_layer_value: number | null
          company_id: string | null
          costing_method: string | null
          item_id: string | null
          qty_on_hand: number | null
          quantity_variance: number | null
          stock_balance_value: number | null
          value_variance: number | null
          warehouse_id: string | null
        }
        Relationships: [
          {
            foreignKeyName: "stock_balances_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_balances_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "stock_balances_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_balances_warehouse_id_fkey"
            columns: ["warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
        ]
      }
      vw_output_vat_review: {
        Row: {
          company_id: string | null
          customer_name: string | null
          customer_tin: string | null
          exempt_sales: number | null
          gross_sales: number | null
          invoice_date: string | null
          output_vat: number | null
          source_doc_id: string | null
          source_doc_type: string | null
          source_module: string | null
          system_no: string | null
          taxable_base: number | null
          transaction_id: string | null
          zero_rated_sales: number | null
        }
        Relationships: [
          {
            foreignKeyName: "tax_detail_entries_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tax_detail_entries_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      vw_outstanding_checks: {
        Row: {
          account_name: string | null
          account_number: string | null
          bank_account_id: string | null
          bank_name: string | null
          check_date: string | null
          check_number: string | null
          company_id: string | null
          cv_number: string | null
          days_outstanding: number | null
          id: string | null
          net_check_amount: number | null
          particulars: string | null
          payee: string | null
          payee_tin: string | null
          status: string | null
          voucher_date: string | null
        }
        Relationships: [
          {
            foreignKeyName: "check_vouchers_bank_account_id_fkey"
            columns: ["bank_account_id"]
            isOneToOne: false
            referencedRelation: "bank_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "check_vouchers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "check_vouchers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      vw_payment_register: {
        Row: {
          check_date: string | null
          check_number: string | null
          company_id: string | null
          created_at: string | null
          date_cleared: string | null
          date_released: string | null
          id: string | null
          reference_number: string | null
          status: string | null
          supplier_name: string | null
          supplier_tin: string | null
          total_amount: number | null
          total_cleared: number | null
          total_ewt: number | null
          voucher_date: string | null
          voucher_number: string | null
        }
        Insert: {
          check_date?: string | null
          check_number?: string | null
          company_id?: string | null
          created_at?: string | null
          date_cleared?: string | null
          date_released?: string | null
          id?: string | null
          reference_number?: string | null
          status?: string | null
          supplier_name?: string | null
          supplier_tin?: string | null
          total_amount?: number | null
          total_cleared?: never
          total_ewt?: number | null
          voucher_date?: string | null
          voucher_number?: string | null
        }
        Update: {
          check_date?: string | null
          check_number?: string | null
          company_id?: string | null
          created_at?: string | null
          date_cleared?: string | null
          date_released?: string | null
          id?: string | null
          reference_number?: string | null
          status?: string | null
          supplier_name?: string | null
          supplier_tin?: string | null
          total_amount?: number | null
          total_cleared?: never
          total_ewt?: number | null
          voucher_date?: string | null
          voucher_number?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "payment_vouchers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_vouchers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      vw_po_line_receipt_progress: {
        Row: {
          company_id: string | null
          description: string | null
          is_over_received: boolean | null
          item_id: string | null
          line_number: number | null
          ordered_qty: number | null
          po_id: string | null
          po_line_id: string | null
          po_number: string | null
          received_qty: number | null
          remaining_qty: number | null
          supplier_id: string | null
        }
        Relationships: [
          {
            foreignKeyName: "purchase_order_lines_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_order_lines_po_id_fkey"
            columns: ["po_id"]
            isOneToOne: false
            referencedRelation: "purchase_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_orders_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_orders_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "purchase_orders_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
      vw_receipt_register: {
        Row: {
          branch_id: string | null
          company_id: string | null
          customer_name_snapshot: string | null
          customer_tin_snapshot: string | null
          receipt_date: string | null
          receipt_id: string | null
          receipt_number: string | null
          reference_number: string | null
          remarks: string | null
          status: string | null
          total_amount: number | null
          total_cwt: number | null
        }
        Insert: {
          branch_id?: string | null
          company_id?: string | null
          customer_name_snapshot?: string | null
          customer_tin_snapshot?: string | null
          receipt_date?: string | null
          receipt_id?: string | null
          receipt_number?: string | null
          reference_number?: string | null
          remarks?: string | null
          status?: string | null
          total_amount?: number | null
          total_cwt?: number | null
        }
        Update: {
          branch_id?: string | null
          company_id?: string | null
          customer_name_snapshot?: string | null
          customer_tin_snapshot?: string | null
          receipt_date?: string | null
          receipt_id?: string | null
          receipt_number?: string | null
          reference_number?: string | null
          remarks?: string | null
          status?: string | null
          total_amount?: number | null
          total_cwt?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "receipts_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receipts_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receipts_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      vw_rr_item_billing_progress: {
        Row: {
          billed_qty: number | null
          company_id: string | null
          item_id: string | null
          received_qty: number | null
          remaining_billable_qty: number | null
          rr_id: string | null
          rr_number: string | null
        }
        Relationships: [
          {
            foreignKeyName: "receiving_report_lines_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receiving_reports_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receiving_reports_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      vw_sales_invoice_register: {
        Row: {
          branch_id: string | null
          company_id: string | null
          customer_name_snapshot: string | null
          customer_tin_snapshot: string | null
          date: string | null
          functional_entity_code: string | null
          functional_entity_id: string | null
          functional_entity_name: string | null
          invoice_id: string | null
          location_code: string | null
          location_id: string | null
          location_name: string | null
          memo: string | null
          project_code: string | null
          project_id: string | null
          project_name: string | null
          reference: string | null
          si_number: string | null
          status: string | null
          total_amount: number | null
          total_exempt_amount: number | null
          total_taxable_amount: number | null
          total_vat_amount: number | null
          total_zero_rated_amount: number | null
          void_reason_id: string | null
        }
        Insert: {
          branch_id?: string | null
          company_id?: string | null
          customer_name_snapshot?: string | null
          customer_tin_snapshot?: string | null
          date?: string | null
          functional_entity_code?: never
          functional_entity_id?: string | null
          functional_entity_name?: never
          invoice_id?: string | null
          location_code?: never
          location_id?: string | null
          location_name?: never
          memo?: string | null
          project_code?: never
          project_id?: string | null
          project_name?: never
          reference?: string | null
          si_number?: string | null
          status?: string | null
          total_amount?: number | null
          total_exempt_amount?: number | null
          total_taxable_amount?: number | null
          total_vat_amount?: number | null
          total_zero_rated_amount?: number | null
          void_reason_id?: string | null
        }
        Update: {
          branch_id?: string | null
          company_id?: string | null
          customer_name_snapshot?: string | null
          customer_tin_snapshot?: string | null
          date?: string | null
          functional_entity_code?: never
          functional_entity_id?: string | null
          functional_entity_name?: never
          invoice_id?: string | null
          location_code?: never
          location_id?: string | null
          location_name?: never
          memo?: string | null
          project_code?: never
          project_id?: string | null
          project_name?: never
          reference?: string | null
          si_number?: string | null
          status?: string | null
          total_amount?: number | null
          total_exempt_amount?: number | null
          total_taxable_amount?: number | null
          total_vat_amount?: number | null
          total_zero_rated_amount?: number | null
          void_reason_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sales_invoices_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoices_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoices_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
          {
            foreignKeyName: "sales_invoices_functional_entity_id_fkey"
            columns: ["functional_entity_id"]
            isOneToOne: false
            referencedRelation: "functional_entities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoices_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoices_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoices_void_reason_id_fkey"
            columns: ["void_reason_id"]
            isOneToOne: false
            referencedRelation: "void_reason_codes"
            referencedColumns: ["id"]
          },
        ]
      }
      vw_sdm_register: {
        Row: {
          company_id: string | null
          created_at: string | null
          dm_date: string | null
          id: string | null
          reason: string | null
          sdm_number: string | null
          status: string | null
          supplier_name: string | null
          supplier_tin: string | null
          total_amount: number | null
        }
        Insert: {
          company_id?: string | null
          created_at?: string | null
          dm_date?: string | null
          id?: string | null
          reason?: string | null
          sdm_number?: string | null
          status?: string | null
          supplier_name?: string | null
          supplier_tin?: string | null
          total_amount?: number | null
        }
        Update: {
          company_id?: string | null
          created_at?: string | null
          dm_date?: string | null
          id?: string | null
          reason?: string | null
          sdm_number?: string | null
          status?: string | null
          supplier_name?: string | null
          supplier_tin?: string | null
          total_amount?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "supplier_debit_memos_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_debit_memos_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      vw_slp_export: {
        Row: {
          address: string | null
          bill_date: string | null
          company_id: string | null
          exempt_purchases: number | null
          gross_purchases: number | null
          input_vat: number | null
          registered_name: string | null
          supplier_tin: string | null
          taxable_base: number | null
          taxable_month: string | null
          zero_rated: number | null
        }
        Relationships: [
          {
            foreignKeyName: "vendor_bills_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_bills_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      vw_supplier_ledger: {
        Row: {
          company_id: string | null
          created_at: string | null
          credit_amount: number | null
          debit_amount: number | null
          description: string | null
          document_id: string | null
          document_number: string | null
          document_type: string | null
          external_ref: string | null
          source_doc_id: string | null
          source_doc_type: string | null
          supplier_id: string | null
          transaction_date: string | null
        }
        Relationships: []
      }
      vw_tax_reference_catalog: {
        Row: {
          code: string | null
          deprecated_at: string | null
          description: string | null
          effective_from: string | null
          effective_to: string | null
          id: string | null
          is_active: boolean | null
          is_current: boolean | null
          rate: number | null
          reference_type: string | null
          tax_category: string | null
        }
        Relationships: []
      }
      vw_trial_balance: {
        Row: {
          account_code: string | null
          account_id: string | null
          account_name: string | null
          account_type: string | null
          company_id: string | null
          fiscal_period_id: string | null
          net_movement: number | null
          normal_balance: string | null
          parent_id: string | null
          period_end: string | null
          period_name: string | null
          period_number: number | null
          period_start: string | null
          total_credit: number | null
          total_debit: number | null
        }
        Relationships: [
          {
            foreignKeyName: "chart_of_accounts_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entries_fiscal_period_id_fkey"
            columns: ["fiscal_period_id"]
            isOneToOne: false
            referencedRelation: "fiscal_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entry_lines_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entry_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entry_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
      vw_vendor_bill_register: {
        Row: {
          bill_date: string | null
          bill_number: string | null
          company_id: string | null
          created_at: string | null
          due_date: string | null
          ewt_deducted: number | null
          id: string | null
          input_vat: number | null
          status: string | null
          supplier_invoice_number: string | null
          supplier_name: string | null
          supplier_tin: string | null
          total_amount: number | null
          total_exempt_amount: number | null
          total_taxable_amount: number | null
          total_zero_rated_amount: number | null
        }
        Insert: {
          bill_date?: string | null
          bill_number?: string | null
          company_id?: string | null
          created_at?: string | null
          due_date?: string | null
          ewt_deducted?: never
          id?: string | null
          input_vat?: number | null
          status?: string | null
          supplier_invoice_number?: string | null
          supplier_name?: string | null
          supplier_tin?: string | null
          total_amount?: number | null
          total_exempt_amount?: number | null
          total_taxable_amount?: number | null
          total_zero_rated_amount?: number | null
        }
        Update: {
          bill_date?: string | null
          bill_number?: string | null
          company_id?: string | null
          created_at?: string | null
          due_date?: string | null
          ewt_deducted?: never
          id?: string | null
          input_vat?: number | null
          status?: string | null
          supplier_invoice_number?: string | null
          supplier_name?: string | null
          supplier_tin?: string | null
          total_amount?: number | null
          total_exempt_amount?: number | null
          total_taxable_amount?: number | null
          total_zero_rated_amount?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "vendor_bills_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vendor_bills_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "vw_company_accounting_config"
            referencedColumns: ["company_id"]
          },
        ]
      }
    }
    Functions: {
      can_admin_company: { Args: { p_company_id: string }; Returns: boolean }
      fn_account_is_leaf: { Args: { p_account_id: string }; Returns: boolean }
      fn_acknowledge_supplier_debit_memo: {
        Args: { p_sdm_id: string }
        Returns: undefined
      }
      fn_add_cost_layer: {
        Args: {
          p_company_id: string
          p_item_id: string
          p_layer_date: string
          p_lot_number?: string
          p_qty: number
          p_ref_doc_id?: string
          p_ref_doc_type?: string
          p_serial_number?: string
          p_unit_cost: number
          p_warehouse_id: string
        }
        Returns: string
      }
      fn_add_filing_reconciling_item: {
        Args: {
          p_amount: number
          p_company_id: string
          p_form_code: string
          p_period: number
          p_reason: string
          p_reference: string
          p_remarks: string
          p_year: number
        }
        Returns: string
      }
      fn_add_percentage_tax_detail: {
        Args: {
          p_atc_code_id: string
          p_branch_id: string
          p_company_id: string
          p_counterparty_id: string
          p_counterparty_name: string
          p_counterparty_tin: string
          p_document_date: string
          p_percentage_tax_code_id: string
          p_source_doc_id: string
          p_source_doc_type: string
          p_tax_amount: number
          p_tax_base: number
          p_tax_code_id: string
          p_tax_period_id: string
          p_tax_rate: number
        }
        Returns: string
      }
      fn_add_posting_line: {
        Args: {
          p_account_id: string
          p_branch_id?: string
          p_cost_center_id?: string
          p_credit?: number
          p_debit?: number
          p_department_id?: string
          p_description: string
          p_functional_entity_id?: string
          p_je_id: string
          p_line_number: number
          p_location_id?: string
          p_project_id?: string
        }
        Returns: string
      }
      fn_add_posting_line_push: {
        Args: {
          p_account_id: string
          p_branch_id?: string
          p_cost_center_id?: string
          p_credit?: number
          p_debit?: number
          p_department_id?: string
          p_description: string
          p_functional_entity_id?: string
          p_je_id: string
          p_line_number: number
          p_line_role?: string
          p_location_id?: string
          p_project_id?: string
          p_source_line_id?: string
        }
        Returns: string
      }
      fn_add_sales_invoice_posting_line: {
        Args: {
          p_account_id: string
          p_branch_id: string
          p_cost_center_id: string
          p_credit: number
          p_debit: number
          p_department_id: string
          p_description: string
          p_functional_entity_id: string
          p_je_id: string
          p_line_number: number
          p_location_id: string
          p_project_id: string
        }
        Returns: undefined
      }
      fn_add_tax_detail: {
        Args: {
          p_atc_code_id: string
          p_branch_id: string
          p_company_id: string
          p_counterparty_id: string
          p_counterparty_name: string
          p_counterparty_tin: string
          p_document_date: string
          p_filing_status?: string
          p_income_nature?: string
          p_is_reversal?: boolean
          p_posting_date: string
          p_reverses_tax_detail_id?: string
          p_source_doc_id: string
          p_source_doc_type: string
          p_source_line_id: string
          p_tax_amount: number
          p_tax_base: number
          p_tax_code_id: string
          p_tax_kind: string
          p_tax_period_id: string
          p_tax_rate: number
          p_vat_code_id: string
        }
        Returns: string
      }
      fn_admin_list_company_users: {
        Args: { p_company_id: string }
        Returns: {
          email: string
          granted_at: string
          last_sign_in_at: string
          membership_id: string
          role: string
          user_id: string
        }[]
      }
      fn_admin_remove_membership: {
        Args: { p_company_id: string; p_user_id: string }
        Returns: undefined
      }
      fn_admin_set_branch_scopes: {
        Args: {
          p_branch_ids: string[]
          p_company_id: string
          p_user_id: string
        }
        Returns: number
      }
      fn_admin_upsert_membership: {
        Args: { p_company_id: string; p_role: string; p_user_id: string }
        Returns: string
      }
      fn_ap_aging_asof: {
        Args: { p_as_of: string; p_company_id: string; p_supplier_id?: string }
        Returns: {
          balance_due: number
          bill_date: string
          bill_id: string
          bill_number: string
          days_overdue: number
          due_date: string
          original_amount: number
          supplier_id: string
          supplier_name: string
        }[]
      }
      fn_ap_subledger_gl_reconciliation_asof: {
        Args: { p_as_of: string; p_company_id: string }
        Returns: {
          as_of_date: string
          company_id: string
          control_account_code: string
          control_account_id: string
          control_account_name: string
          gl_balance: number
          is_reconciled: boolean
          ledger_code: string
          subledger_balance: number
          variance: number
        }[]
      }
      fn_apply_vendor_credit: {
        Args: {
          p_amount: number
          p_bill_id: string
          p_credit_id: string
          p_date?: string
          p_remarks?: string
        }
        Returns: string
      }
      fn_approval_inbox: {
        Args: { p_company_id?: string }
        Returns: {
          action_type: string
          branch_id: string
          company_id: string
          currency_code: string
          current_step_sequence: number
          module_type: string
          record_version: string
          request_id: string
          requester_id: string
          source_document_amount: number
          source_document_id: string
          source_document_no: string
          source_document_type: string
          status: string
          submitted_at: string
          workflow_name: string
        }[]
      }
      fn_approval_source_permission_action: {
        Args: { p_action_type: string }
        Returns: string
      }
      fn_approval_step_has_candidate: {
        Args: { p_branch_id: string; p_step_id: string }
        Returns: boolean
      }
      fn_approve_approval_request: {
        Args: {
          p_current_record_version: string
          p_remarks?: string
          p_request_id: string
        }
        Returns: Json
      }
      fn_approve_petty_cash_voucher: {
        Args: { p_pcv_id: string }
        Returns: undefined
      }
      fn_approve_petty_cash_voucher_source_locked_impl: {
        Args: { p_pcv_id: string }
        Returns: undefined
      }
      fn_approve_purchase_order: {
        Args: { p_po_id: string }
        Returns: undefined
      }
      fn_approve_sales_invoice: {
        Args: { p_invoice_id: string }
        Returns: undefined
      }
      fn_approve_vendor_bill: {
        Args: { p_bill_id: string }
        Returns: undefined
      }
      fn_ar_aging_asof: {
        Args: { p_as_of: string; p_company_id: string; p_customer_id?: string }
        Returns: {
          balance_due: number
          customer_id: string
          customer_name: string
          days_overdue: number
          due_date: string
          invoice_date: string
          invoice_id: string
          original_amount: number
          si_number: string
        }[]
      }
      fn_ar_subledger_gl_reconciliation_asof: {
        Args: { p_as_of: string; p_company_id: string }
        Returns: {
          as_of_date: string
          company_id: string
          control_account_code: string
          control_account_id: string
          control_account_name: string
          gl_balance: number
          is_reconciled: boolean
          ledger_code: string
          subledger_balance: number
          variance: number
        }[]
      }
      fn_assert_bill_within_receipt: {
        Args: { p_bill_id: string }
        Returns: undefined
      }
      fn_assert_manual_postable: {
        Args: { p_account_id: string; p_as_of?: string }
        Returns: undefined
      }
      fn_assert_no_unlinked_delivered_stock: {
        Args: { p_invoice_id: string }
        Returns: undefined
      }
      fn_assert_postable_leaf: {
        Args: { p_account_id: string; p_as_of?: string }
        Returns: undefined
      }
      fn_assert_posting_source: {
        Args: {
          p_company_id: string
          p_document_type: string
          p_source_id: string
        }
        Returns: Json
      }
      fn_assert_receipt_within_po: {
        Args: { p_rr_id: string }
        Returns: undefined
      }
      fn_assert_sales_invoice_dimension: {
        Args: {
          p_as_of: string
          p_branch_id: string
          p_company_id: string
          p_context: string
          p_dimension_id: string
          p_dimension_type: string
        }
        Returns: undefined
      }
      fn_assert_source_journal_link: {
        Args: {
          p_company_id: string
          p_document_type: string
          p_journal_entry_id: string
          p_source_id: string
        }
        Returns: undefined
      }
      fn_assert_transaction_dimension: {
        Args: {
          p_as_of: string
          p_branch_id: string
          p_company_id: string
          p_context: string
          p_dimension_id: string
          p_dimension_type: string
        }
        Returns: undefined
      }
      fn_atc_code_is_current: {
        Args: {
          p_as_of_date?: string
          p_atc_id: string
          p_tax_category: string
        }
        Returns: boolean
      }
      fn_atc_code_set_active: {
        Args: { p_id: string; p_is_active: boolean; p_reason?: string }
        Returns: undefined
      }
      fn_atc_code_succeed: {
        Args: {
          p_description?: string
          p_effective_from: string
          p_id: string
          p_rate: number
          p_reason?: string
        }
        Returns: string
      }
      fn_atc_code_upsert: {
        Args: {
          p_code: string
          p_description: string
          p_effective_from?: string
          p_effective_to?: string
          p_id?: string
          p_is_active?: boolean
          p_rate: number
          p_reason?: string
          p_supersedes_id?: string
          p_tax_category: string
        }
        Returns: string
      }
      fn_atc_code_used: { Args: { p_atc_id: string }; Returns: boolean }
      fn_atc_version_asof: {
        Args: { p_as_of?: string; p_code: string; p_tax_category: string }
        Returns: string
      }
      fn_begin_source_posting: {
        Args: {
          p_document_type: string
          p_done_statuses?: string[]
          p_ready_statuses?: string[]
          p_source_id: string
        }
        Returns: Json
      }
      fn_bir_form_mapping_delete: {
        Args: { p_mapping_id: string; p_reason?: string }
        Returns: undefined
      }
      fn_bir_form_mapping_upsert: {
        Args: {
          p_form_id: string
          p_line_identifier: string
          p_mapping_id?: string
          p_reason?: string
          p_source_id?: string
          p_source_type: string
        }
        Returns: string
      }
      fn_bir_form_set_active: {
        Args: { p_form_id: string; p_is_active: boolean; p_reason?: string }
        Returns: undefined
      }
      fn_bir_form_upsert: {
        Args: {
          p_description: string
          p_form_number: string
          p_frequency: string
          p_is_active?: boolean
          p_reason?: string
        }
        Returns: string
      }
      fn_books_export_reconciliation: {
        Args: {
          p_book_type: string
          p_company_id: string
          p_date_from: string
          p_date_to: string
          p_rows: Json
        }
        Returns: Json
      }
      fn_bounce_receipt: { Args: { p_receipt_id: string }; Returns: undefined }
      fn_bt_reverse_je: {
        Args: {
          p_branch_id: string
          p_company_id: string
          p_je_number: string
          p_memo: string
          p_orig_je_id: string
          p_ref_id: string
          p_ref_type: string
        }
        Returns: string
      }
      fn_build_posting_context: {
        Args: {
          p_as_of?: string
          p_branch_id: string
          p_company_id: string
          p_cost_center_id?: string
          p_department_id?: string
          p_functional_entity_id?: string
          p_location_id?: string
          p_posting_date: string
          p_posting_origin?: string
          p_project_id?: string
          p_source_id: string
          p_source_number: string
          p_source_type: string
        }
        Returns: Json
      }
      fn_business_tax_codes_asof: {
        Args: {
          p_as_of?: string
          p_company_id: string
          p_transaction_type?: string
        }
        Returns: {
          atc_code: string
          classification: string
          code: string
          description: string
          effective_from: string
          effective_to: string
          form_type: string
          id: string
          rate: number
          tax_code_id: string
          tax_family: string
          transaction_type: string
        }[]
      }
      fn_calculate_tax: {
        Args: { p_context: Json }
        Returns: Database["public"]["CompositeTypes"]["tax_component"][]
        SetofOptions: {
          from: "*"
          to: "tax_component"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      fn_can_access_company_branch: {
        Args: { p_branch_id?: string; p_company_id: string }
        Returns: boolean
      }
      fn_can_decide_approval_request: {
        Args: {
          p_company_id: string
          p_document_type: string
          p_module_type: string
        }
        Returns: boolean
      }
      fn_can_master_data_permission: {
        Args: { p_action: string; p_company_id: string; p_master_key: string }
        Returns: boolean
      }
      fn_can_perform: {
        Args: {
          p_action: string
          p_company_id: string
          p_document_type?: string
        }
        Returns: boolean
      }
      fn_can_provision_company: { Args: never; Returns: boolean }
      fn_can_submit_approval_request: {
        Args: {
          p_action_type: string
          p_company_id: string
          p_document_type: string
          p_module_type: string
        }
        Returns: boolean
      }
      fn_cancel_amortization_schedule: {
        Args: { p_schedule_id: string }
        Returns: undefined
      }
      fn_cancel_bank_adjustment: {
        Args: { p_ba_id: string; p_memo?: string }
        Returns: undefined
      }
      fn_cancel_check_voucher: {
        Args: { p_cv_id: string; p_memo?: string }
        Returns: undefined
      }
      fn_cancel_fund_transfer: {
        Args: { p_ft_id: string; p_memo?: string }
        Returns: undefined
      }
      fn_cancel_inter_branch_transfer: {
        Args: { p_ibt_id: string; p_memo?: string }
        Returns: undefined
      }
      fn_cancel_payment_voucher: {
        Args: { p_memo?: string; p_voucher_id: string }
        Returns: undefined
      }
      fn_cancel_petty_cash_voucher: {
        Args: { p_memo?: string; p_pcv_id: string }
        Returns: undefined
      }
      fn_cancel_purchase_order: {
        Args: { p_po_id: string }
        Returns: undefined
      }
      fn_cancel_revenue_recognition_schedule: {
        Args: { p_schedule_id: string }
        Returns: undefined
      }
      fn_cas_issuance_document_date: {
        Args: { p_source_id: string; p_source_table: string }
        Returns: string
      }
      fn_claim_form2307_received: {
        Args: {
          p_claim_tax_quarter: number
          p_claim_tax_year: number
          p_claimed_date?: string
          p_tracking_id: string
        }
        Returns: undefined
      }
      fn_close_accounting_period: {
        Args: {
          p_company_id: string
          p_fiscal_period_id: string
          p_note?: string
        }
        Returns: string
      }
      fn_close_accounting_quarter: {
        Args: {
          p_company_id: string
          p_fiscal_year_id: string
          p_note?: string
          p_quarter: number
        }
        Returns: number
      }
      fn_close_fiscal_year: {
        Args: {
          p_close_date?: string
          p_company_id: string
          p_fiscal_year_id: string
        }
        Returns: string
      }
      fn_company_ap_ewt_policy: {
        Args: { p_company_id: string }
        Returns: string
      }
      fn_company_ewt_payable_enabled: {
        Args: { p_company_id: string }
        Returns: boolean
      }
      fn_company_percentage_tax_registered_asof: {
        Args: { p_as_of?: string; p_company_id: string }
        Returns: boolean
      }
      fn_company_tax_registration_asof: {
        Args: { p_as_of?: string; p_company_id: string }
        Returns: string
      }
      fn_company_twa_auto_ewt_enabled: {
        Args: { p_company_id: string; p_document_date?: string }
        Returns: boolean
      }
      fn_comparative_financial_statement_report: {
        Args: {
          p_branch_id?: string
          p_company_id: string
          p_period_end: string
          p_period_start: string
          p_prior_end?: string
          p_prior_start?: string
          p_statement: string
        }
        Returns: {
          comparison_basis: string
          current_amount: number
          current_closing: number
          current_movement: number
          current_opening: number
          depth: number
          display_order: number
          is_subtotal: boolean
          line_code: string
          line_label: string
          line_role: string
          parent_code: string
          prior_amount: number
          prior_closing: number
          prior_movement: number
          prior_opening: number
          variance_amount: number
          variance_percent: number
        }[]
      }
      fn_complete_purchase_return: {
        Args: { p_return_id: string }
        Returns: undefined
      }
      fn_complete_purchase_return_inventory_legacy_20260808: {
        Args: { p_return_id: string }
        Returns: undefined
      }
      fn_complete_purchase_return_source_locked_impl: {
        Args: { p_return_id: string }
        Returns: undefined
      }
      fn_complete_secondary_posting: {
        Args: {
          p_document_type: string
          p_journal_entry_id?: string
          p_source_id: string
        }
        Returns: string
      }
      fn_compute_depr_schedule: {
        Args: {
          p_cost: number
          p_method: string
          p_months: number
          p_salvage: number
          p_start_date: string
        }
        Returns: {
          accumulated_depr_after: number
          depreciation_amount: number
          entry_date: string
          net_book_value_after: number
          period_number: number
        }[]
      }
      fn_compute_ewt_remitted_prior: {
        Args: { p_company_id: string; p_quarter: number; p_year: number }
        Returns: number
      }
      fn_compute_ewt_return: {
        Args: { p_company_id: string; p_quarter: number; p_year: number }
        Returns: {
          total_ewt_withheld: number
          total_tax_base: number
        }[]
      }
      fn_compute_percentage_tax_return: {
        Args: { p_company_id: string; p_quarter: number; p_year: number }
        Returns: {
          atc_code: string
          document_count: number
          pt_code: string
          tax_code: string
          tax_due: number
          tax_rate: number
          taxable_base: number
        }[]
      }
      fn_confirm_receiving_report: {
        Args: { p_rr_id: string }
        Returns: undefined
      }
      fn_confirm_receiving_report_status_core_20260718: {
        Args: { p_rr_id: string }
        Returns: undefined
      }
      fn_consume_cost_layers: {
        Args: {
          p_company_id: string
          p_item_id: string
          p_lot_number?: string
          p_qty: number
          p_serial_number?: string
          p_warehouse_id: string
        }
        Returns: {
          layer_id: string
          qty_consumed: number
          unit_cost: number
        }[]
      }
      fn_create_amortization_schedule: {
        Args: {
          p_asset_account_id: string
          p_branch_id: string
          p_company_id: string
          p_description: string
          p_expense_account_id: string
          p_schedule_name: string
          p_start_date: string
          p_total_amount: number
          p_total_periods: number
        }
        Returns: string
      }
      fn_create_fiscal_year: {
        Args: {
          p_company_id: string
          p_start_date: string
          p_year_name?: string
        }
        Returns: string
      }
      fn_create_posted_journal_entry: {
        Args: {
          p_assert_source?: boolean
          p_auto_reverse?: boolean
          p_branch_id: string
          p_company_id: string
          p_description: string
          p_emit_origin_update?: boolean
          p_entry_class?: string
          p_fiscal_period_id?: string
          p_je_date: string
          p_je_number: string
          p_posting_origin?: string
          p_reference_doc_id: string
          p_reference_doc_type: string
          p_status?: string
          p_total_credit?: number
          p_total_debit?: number
        }
        Returns: string
      }
      fn_create_revenue_recognition_schedule: {
        Args: {
          p_branch_id: string
          p_company_id: string
          p_deferred_revenue_account_id: string
          p_description: string
          p_revenue_account_id: string
          p_schedule_name: string
          p_start_date: string
          p_total_amount: number
          p_total_periods: number
        }
        Returns: string
      }
      fn_customer_ledger_asof: {
        Args: { p_as_of: string; p_company_id: string; p_customer_id?: string }
        Returns: {
          company_id: string
          created_at: string
          credit_amount: number
          customer_id: string
          customer_name: string
          debit_amount: number
          description: string
          document_id: string
          document_number: string
          document_type: string
          running_balance: number
          source_doc_id: string
          source_doc_type: string
          transaction_date: string
        }[]
      }
      fn_delete_filing_reconciling_item: {
        Args: { p_item_id: string }
        Returns: undefined
      }
      fn_demo_reset_bypass_authorized: { Args: never; Returns: boolean }
      fn_derive_journal_number: {
        Args: {
          p_branch_id?: string
          p_company_id?: string
          p_source_number?: string
          p_source_type: string
        }
        Returns: string
      }
      fn_dispose_fixed_asset: { Args: { p_data: Json }; Returns: string }
      fn_ensure_stock_balance: {
        Args: {
          p_company_id: string
          p_item_id: string
          p_warehouse_id: string
        }
        Returns: {
          company_id: string
          id: string
          item_id: string
          last_issue_date: string | null
          last_receipt_date: string | null
          projection_authority: string
          projection_fingerprint: string | null
          projection_version_id: string | null
          projection_watermark_sequence: number | null
          qty_on_hand: number
          qty_reserved: number
          total_cost: number
          updated_at: string
          wac_unit_cost: number
          warehouse_id: string
        }
        SetofOptions: {
          from: "*"
          to: "stock_balances"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      fn_execute_recurring_template: {
        Args: { p_je_date: string; p_template_id: string }
        Returns: string
      }
      fn_execute_recurring_template_source_locked_impl: {
        Args: { p_je_date: string; p_template_id: string }
        Returns: string
      }
      fn_export_csv_line: { Args: { p_cells: string[] }; Returns: string }
      fn_export_dat_cell: { Args: { p_value: string }; Returns: string }
      fn_export_dat_file_name: {
        Args: { p_file_name: string }
        Returns: string
      }
      fn_export_dat_numeric: { Args: { p_value: string }; Returns: number }
      fn_export_dat_tin: { Args: { p_value: string }; Returns: string }
      fn_export_decimal: { Args: { p_value: number }; Returns: string }
      fn_export_master_data: {
        Args: {
          p_company_id: string
          p_include_inactive?: boolean
          p_master_key: string
        }
        Returns: Json
      }
      fn_export_master_data_package: {
        Args: {
          p_company_id: string
          p_include_global?: boolean
          p_include_inactive?: boolean
        }
        Returns: Json
      }
      fn_filing_artifact_export: {
        Args: {
          p_company_id: string
          p_form_code: string
          p_format?: string
          p_period: number
          p_year: number
        }
        Returns: {
          content: string
          line_number: number
        }[]
      }
      fn_filing_period_bounds: {
        Args: { p_period: number; p_period_basis: string; p_year: number }
        Returns: Record<string, unknown>
      }
      fn_filing_reconciliation: {
        Args: {
          p_company_id: string
          p_form_code: string
          p_period: number
          p_year: number
        }
        Returns: {
          gl_account_code: string
          gl_account_id: string
          gl_account_name: string
          gl_amount: number
          is_reconciled: boolean
          ledger_tax_amount: number
          ledger_tax_base: number
          tax_kind: string
          variance: number
        }[]
      }
      fn_filing_reconciling_items: {
        Args: {
          p_company_id: string
          p_form_code: string
          p_period: number
          p_year: number
        }
        Returns: {
          amount: number
          created_at: string
          created_by: string
          id: string
          line_number: number
          reason: string
          reference: string
          remarks: string
        }[]
      }
      fn_filing_working_paper: {
        Args: {
          p_company_id: string
          p_form_code: string
          p_period: number
          p_year: number
        }
        Returns: {
          atc_code: string
          classification: string
          counterparty_id: string
          counterparty_name: string
          counterparty_tin: string
          document_count: number
          tax_amount: number
          tax_base: number
          tax_code: string
          tax_kind: string
          tax_rate: number
          vat_code: string
        }[]
      }
      fn_finalize_journal_entry: {
        Args: {
          p_auto_reversal_original_je_id?: string
          p_discard_journal?: boolean
          p_je_id: string
          p_link_reference_doc_id?: string
          p_link_reference_doc_type?: string
          p_link_source?: boolean
          p_mark_auto_reversal?: boolean
          p_persist_totals?: boolean
          p_total_credit?: number
          p_total_debit?: number
        }
        Returns: undefined
      }
      fn_financial_statement_line_accounts: {
        Args: {
          p_branch_id?: string
          p_company_id: string
          p_line_code: string
          p_period_end: string
          p_period_start: string
          p_prior_end?: string
          p_prior_start?: string
          p_statement: string
        }
        Returns: {
          account_code: string
          account_id: string
          account_name: string
          account_type: string
          comparison_basis: string
          current_amount: number
          prior_amount: number
          variance_amount: number
          variance_percent: number
        }[]
      }
      fn_financial_statement_notes: {
        Args: {
          p_company_id: string
          p_period_end: string
          p_period_start: string
          p_prior_end?: string
          p_prior_start?: string
        }
        Returns: {
          is_configured: boolean
          item_label: string
          item_order: number
          item_source: string
          item_value: string
          note_code: string
          note_order: number
          note_title: string
        }[]
      }
      fn_financial_statement_report: {
        Args: {
          p_branch_id?: string
          p_company_id: string
          p_period_end: string
          p_period_start: string
          p_presentation_asof?: string
          p_statement: string
        }
        Returns: {
          closing_amount: number
          depth: number
          display_order: number
          is_subtotal: boolean
          line_code: string
          line_label: string
          line_role: string
          movement_amount: number
          opening_amount: number
          parent_code: string
        }[]
      }
      fn_fiscal_close_engine_origin: {
        Args: { p_context: string }
        Returns: boolean
      }
      fn_form2307_period_bounds: {
        Args: { p_quarter: number; p_year: number }
        Returns: Record<string, unknown>
      }
      fn_form2307_report_payload: {
        Args: {
          p_issuance: Database["public"]["Tables"]["form_2307_issuances"]["Row"]
        }
        Returns: Json
      }
      fn_format_ph_tin: {
        Args: { p_default_branch?: string; p_value: string }
        Returns: string
      }
      fn_format_ph_tin_branch: { Args: { p_value: string }; Returns: string }
      fn_fs_line_is_descendant: {
        Args: { p_ancestor_id: string; p_line_id: string }
        Returns: boolean
      }
      fn_fs_presentation_sign: {
        Args: {
          p_is_cash_equivalent: boolean
          p_normal_balance: string
          p_statement: string
        }
        Returns: number
      }
      fn_general_ledger_report: {
        Args: {
          p_account_id?: string
          p_account_types?: string[]
          p_branch_id?: string
          p_company_id: string
          p_cost_center_id?: string
          p_date_from?: string
          p_date_to?: string
          p_department_id?: string
          p_entry_classes?: string[]
          p_je_id?: string
          p_limit?: number
          p_offset?: number
          p_reference_doc_id?: string
          p_reference_doc_type?: string
        }
        Returns: {
          account_code: string
          account_id: string
          account_name: string
          account_type: string
          branch_id: string
          company_id: string
          cost_center_id: string
          credit_amount: number
          debit_amount: number
          department_id: string
          entry_class: string
          fiscal_period_id: string
          is_auto_reversal: boolean
          je_date: string
          je_description: string
          je_id: string
          je_number: string
          je_status: string
          line_description: string
          line_id: string
          line_number: number
          normal_balance: string
          period_credit: number
          period_debit: number
          period_end: string
          period_name: string
          period_start: string
          reference_doc_id: string
          reference_doc_type: string
          reversed_by_je_id: string
          total_rows: number
        }[]
      }
      fn_generate_ewt_return: {
        Args: { p_company_id: string; p_quarter: number; p_year: number }
        Returns: Json
      }
      fn_generate_filing_artifact: {
        Args: {
          p_company_id: string
          p_form_code: string
          p_period: number
          p_year: number
        }
        Returns: Json
      }
      fn_generate_fiscal_periods: {
        Args: { p_fiscal_year_id: string }
        Returns: number
      }
      fn_generate_form_2307_issued: {
        Args: {
          p_company_id: string
          p_tax_quarter: number
          p_tax_year: number
        }
        Returns: Json
      }
      fn_generate_pt_return: {
        Args: { p_company_id: string; p_quarter: number; p_year: number }
        Returns: Json
      }
      fn_generate_tax_calendar: {
        Args: { p_company_id: string; p_fiscal_year: number }
        Returns: undefined
      }
      fn_generate_vat_return: {
        Args: {
          p_company_id: string
          p_input_vat_carried_over?: number
          p_quarter: number
          p_vat_paid_prior_months?: number
          p_year: number
        }
        Returns: Json
      }
      fn_get_accounting_trace: {
        Args: {
          p_journal_entry_id?: string
          p_source_doc_id?: string
          p_source_doc_type?: string
        }
        Returns: Json
      }
      fn_get_approval_decision: {
        Args: {
          p_action_type: string
          p_amount?: number
          p_as_of?: string
          p_branch_id: string
          p_company_id: string
          p_currency_code?: string
          p_document_type: string
          p_module_type: string
        }
        Returns: Json
      }
      fn_get_approval_request_status: {
        Args: { p_request_id: string }
        Returns: Json
      }
      fn_get_report_snapshot_trace_links: {
        Args: { p_report_snapshot_id: string }
        Returns: {
          accounting_trace_route: string
          general_ledger_route: string
          journal_entry_id: string
          journal_route: string
          module_route: string
          report_snapshot_id: string
          source_date: string
          source_doc_id: string
          source_doc_type: string
          source_number: string
          source_route: string
          trace_context: Json
        }[]
      }
      fn_get_report_trace_set: {
        Args: {
          p_company_id: string
          p_filters?: Json
          p_report_family: string
        }
        Returns: {
          accounting_trace_route: string
          general_ledger_route: string
          journal_entry_id: string
          journal_route: string
          module_route: string
          report_family: string
          report_record_id: string
          source_date: string
          source_doc_id: string
          source_doc_type: string
          source_number: string
          source_route: string
          trace_context: Json
        }[]
      }
      fn_gl_account_ledger_page: {
        Args: {
          p_account_id: string
          p_company_id: string
          p_date_from: string
          p_date_to: string
          p_je_id?: string
          p_limit?: number
          p_offset?: number
        }
        Returns: {
          account_code: string
          account_id: string
          account_name: string
          account_type: string
          branch_id: string
          company_id: string
          cost_center_id: string
          credit_amount: number
          debit_amount: number
          department_id: string
          entry_class: string
          fiscal_period_id: string
          is_auto_reversal: boolean
          je_date: string
          je_description: string
          je_id: string
          je_number: string
          je_status: string
          line_description: string
          line_id: string
          line_number: number
          normal_balance: string
          period_end: string
          period_name: string
          period_start: string
          reference_doc_id: string
          reference_doc_type: string
          reversed_by_je_id: string
          running_balance: number
        }[]
      }
      fn_gl_account_ledger_summary: {
        Args: {
          p_account_id: string
          p_company_id: string
          p_date_from: string
          p_date_to: string
          p_je_id?: string
        }
        Returns: {
          account_id: string
          closing_balance: number
          normal_balance: string
          opening_balance: number
          period_credit: number
          period_debit: number
          total_rows: number
        }[]
      }
      fn_gl_impact_payload: {
        Args: { p_je_id: string; p_mode?: string; p_rule_explanation?: string }
        Returns: Json
      }
      fn_gl_report_limit: { Args: { p_limit: number }; Returns: number }
      fn_gl_report_offset: { Args: { p_offset: number }; Returns: number }
      fn_has_enforced_master_data_sod_conflict: {
        Args: {
          p_action_type: string
          p_company_id: string
          p_master_key: string
        }
        Returns: boolean
      }
      fn_ia5_create_dormant_policy_bundle: {
        Args: {
          p_actor_id: string
          p_branch_id: string
          p_company_id: string
          p_costing_method: string
          p_effective_from: string
          p_effective_to: string
          p_item_id: string
          p_quantity_scale: number
          p_scope_type: string
          p_transaction_currency_code: string
          p_transaction_currency_scale: number
          p_warehouse_id: string
        }
        Returns: Json
      }
      fn_ia5_derive_unit_rate: {
        Args: { p_authoritative_amount: number; p_base_quantity: number }
        Returns: number
      }
      fn_ia5_quantize_exact:
        | {
            Args: { p_label?: string; p_scale: number; p_value: number }
            Returns: number
          }
        | {
            Args: { p_label?: string; p_scale: number; p_value: number }
            Returns: number
          }
      fn_ia5_record_dormant_inventory_occurrence: {
        Args: {
          p_actor_id: string
          p_company_id: string
          p_events: Json
          p_idempotency_key: string
          p_occurred_at: string
          p_request_fingerprint: string
          p_source_document_id: string
          p_source_document_type: string
          p_source_line_id: string
          p_source_occurrence_sequence: number
          p_source_transition: string
        }
        Returns: Json
      }
      fn_import_master_data: {
        Args: {
          p_company_id: string
          p_idempotency_key?: string
          p_master_key: string
          p_options?: Json
          p_preview?: boolean
          p_rows: Json
        }
        Returns: Json
      }
      fn_import_master_data_mdp15_core: {
        Args: {
          p_company_id: string
          p_idempotency_key?: string
          p_master_key: string
          p_options?: Json
          p_preview?: boolean
          p_rows: Json
        }
        Returns: Json
      }
      fn_invalidate_form2307_received_for_receipt: {
        Args: { p_reason?: string; p_receipt_id: string }
        Returns: undefined
      }
      fn_is_account_postable: {
        Args: { p_account_id: string; p_as_of?: string }
        Returns: boolean
      }
      fn_is_bir_config_maintainer: {
        Args: { p_user?: string }
        Returns: boolean
      }
      fn_is_valid_approval_candidate: {
        Args: {
          p_approver_role_code: string
          p_approver_type: string
          p_approver_user_id: string
          p_branch_id: string
          p_company_id: string
          p_user_id: string
        }
        Returns: boolean
      }
      fn_is_valid_attribution: {
        Args: { p_company_id: string; p_employee_id: string; p_kind: string }
        Returns: boolean
      }
      fn_is_valid_dimension: {
        Args: {
          p_as_of?: string
          p_branch_id?: string
          p_company_id: string
          p_dimension_id: string
          p_dimension_type: string
        }
        Returns: boolean
      }
      fn_is_valid_lifecycle_transition: {
        Args: { p_new: string; p_old: string }
        Returns: boolean
      }
      fn_issue_inventory: { Args: { p_data: Json }; Returns: Json }
      fn_issue_inventory_from_layer: { Args: { p_data: Json }; Returns: Json }
      fn_item_costing_method: { Args: { p_item_id: string }; Returns: string }
      fn_item_negative_stock_policy: {
        Args: { p_item_id: string }
        Returns: string
      }
      fn_log_bir_config_change: {
        Args: {
          p_action: string
          p_new: Json
          p_old: Json
          p_reason: string
          p_record: string
          p_table: string
        }
        Returns: undefined
      }
      fn_map_company_fs_accounts: {
        Args: { p_company_id: string }
        Returns: number
      }
      fn_mark_tax_event_filed: {
        Args: { p_date_filed: string; p_efps_ref?: string; p_event_id: string }
        Returns: undefined
      }
      fn_master_data_import_template: {
        Args: { p_master_key: string }
        Returns: Json
      }
      fn_master_data_key_for_table: {
        Args: { p_table_name: string }
        Returns: string
      }
      fn_master_data_sod_conflicts_for_current_user: {
        Args: { p_company_id: string }
        Returns: {
          conflict_code: string
          enforcement_mode: string
          left_permission_code: string
          notes: string
          right_permission_code: string
          severity: string
        }[]
      }
      fn_mdp08_module_accounting_config: {
        Args: { p_context: Json }
        Returns: Json
      }
      fn_mdp08_module_coa: { Args: { p_context: Json }; Returns: Json }
      fn_mdp08_module_compliance: { Args: { p_context: Json }; Returns: Json }
      fn_mdp08_module_dimensions: { Args: { p_context: Json }; Returns: Json }
      fn_mdp08_module_fiscal_calendar: {
        Args: { p_context: Json }
        Returns: Json
      }
      fn_mdp08_module_inventory_config: {
        Args: { p_context: Json }
        Returns: Json
      }
      fn_mdp08_module_number_series: {
        Args: { p_context: Json }
        Returns: Json
      }
      fn_mdp08_module_payment_modes: {
        Args: { p_context: Json }
        Returns: Json
      }
      fn_mdp08_module_percentage_tax: {
        Args: { p_context: Json }
        Returns: Json
      }
      fn_mdp08_module_uom: { Args: { p_context: Json }; Returns: Json }
      fn_mdp08_try_date: { Args: { p_value: string }; Returns: string }
      fn_mdp08_try_uuid: { Args: { p_value: string }; Returns: string }
      fn_mdp15_export_master_data_impl: {
        Args: {
          p_company_id: string
          p_include_inactive?: boolean
          p_master_key: string
        }
        Returns: Json
      }
      fn_mdp15_find_record_id: {
        Args: { p_company_id: string; p_master_key: string; p_row: Json }
        Returns: string
      }
      fn_mdp15_import_columns: {
        Args: { p_table_name: string; p_table_schema: string }
        Returns: string[]
      }
      fn_next_document_number: {
        Args: {
          p_branch_id: string
          p_company_id: string
          p_document_code: string
        }
        Returns: string
      }
      fn_normalize_report_source_type: {
        Args: { p_hint: string }
        Returns: string
      }
      fn_open_next_fiscal_year: {
        Args: { p_company_id: string; p_fiscal_year_id: string }
        Returns: string
      }
      fn_opening_balance_summary: {
        Args: { p_batch_id: string }
        Returns: Json
      }
      fn_party_tin_duplicates: {
        Args: {
          p_company_id: string
          p_exclude_id?: string
          p_party_type: string
          p_tin: string
        }
        Returns: {
          party_code: string
          party_id: string
          party_name: string
        }[]
      }
      fn_percentage_tax_code_used: {
        Args: { p_percentage_tax_code_id: string }
        Returns: boolean
      }
      fn_percentage_tax_gl_reconciliation: {
        Args: { p_company_id: string; p_date_from: string; p_date_to: string }
        Returns: {
          gl_account_code: string
          gl_account_id: string
          gl_account_name: string
          gl_amount: number
          is_reconciled: boolean
          ledger_tax_amount: number
          ledger_tax_base: number
          variance: number
        }[]
      }
      fn_percentage_tax_return_period: {
        Args: { p_quarter: number; p_year: number }
        Returns: Record<string, unknown>
      }
      fn_period_close_readiness: {
        Args: { p_company_id: string; p_fiscal_period_id: string }
        Returns: Json
      }
      fn_ph_tin_digits: { Args: { p_value: string }; Returns: string }
      fn_post_amortization_entry: {
        Args: { p_entry_id: string }
        Returns: string
      }
      fn_post_amortization_entry_source_locked_impl: {
        Args: { p_entry_id: string }
        Returns: string
      }
      fn_post_bank_adjustment: { Args: { p_ba_id: string }; Returns: undefined }
      fn_post_bank_adjustment_source_locked_impl: {
        Args: { p_ba_id: string }
        Returns: undefined
      }
      fn_post_cash_purchase: { Args: { p_cp_id: string }; Returns: undefined }
      fn_post_cash_purchase_core_20260718: {
        Args: { p_cp_id: string }
        Returns: undefined
      }
      fn_post_cash_purchase_source_locked_impl: {
        Args: { p_cp_id: string }
        Returns: undefined
      }
      fn_post_check_voucher: { Args: { p_cv_id: string }; Returns: undefined }
      fn_post_credit_memo: { Args: { p_cm_id: string }; Returns: undefined }
      fn_post_credit_memo_source_locked_impl: {
        Args: { p_cm_id: string }
        Returns: undefined
      }
      fn_post_credit_memo_vat_lump_impl: {
        Args: { p_cm_id: string }
        Returns: undefined
      }
      fn_post_debit_memo: { Args: { p_dm_id: string }; Returns: undefined }
      fn_post_debit_memo_source_locked_impl: {
        Args: { p_dm_id: string }
        Returns: undefined
      }
      fn_post_debit_memo_vat_lump_impl: {
        Args: { p_dm_id: string }
        Returns: undefined
      }
      fn_post_delivery_receipt: {
        Args: { p_dr_id: string }
        Returns: undefined
      }
      fn_post_delivery_receipt_costing_legacy_20260808: {
        Args: { p_dr_id: string }
        Returns: undefined
      }
      fn_post_depreciation_entry: {
        Args: { p_entry_id: string }
        Returns: string
      }
      fn_post_depreciation_entry_source_locked_impl: {
        Args: { p_entry_id: string }
        Returns: string
      }
      fn_post_fund_transfer: { Args: { p_ft_id: string }; Returns: undefined }
      fn_post_fund_transfer_source_locked_impl: {
        Args: { p_ft_id: string }
        Returns: undefined
      }
      fn_post_goods_issue: { Args: { p_issue_id: string }; Returns: string }
      fn_post_goods_issue_source_locked_impl: {
        Args: { p_issue_id: string }
        Returns: string
      }
      fn_post_inter_branch_transfer: {
        Args: { p_ibt_id: string }
        Returns: undefined
      }
      fn_post_inter_branch_transfer_source_locked_impl: {
        Args: { p_ibt_id: string }
        Returns: undefined
      }
      fn_post_manual_je: {
        Args: {
          p_auto_reverse: boolean
          p_branch_id: string
          p_company_id: string
          p_description: string
          p_entry_class?: string
          p_je_date: string
          p_lines: Json
          p_reference_doc_type: string
        }
        Returns: string
      }
      fn_post_opening_balance: { Args: { p_batch_id: string }; Returns: string }
      fn_post_payment_voucher: {
        Args: { p_voucher_id: string }
        Returns: undefined
      }
      fn_post_petty_cash_replenishment: {
        Args: { p_pcr_id: string }
        Returns: undefined
      }
      fn_post_petty_cash_replenishment_source_locked_impl: {
        Args: { p_pcr_id: string }
        Returns: undefined
      }
      fn_post_physical_count: { Args: { p_sheet_id: string }; Returns: string }
      fn_post_physical_count_source_locked_impl: {
        Args: { p_sheet_id: string }
        Returns: string
      }
      fn_post_receipt: { Args: { p_receipt_id: string }; Returns: undefined }
      fn_post_receiving_report: { Args: { p_rr_id: string }; Returns: string }
      fn_post_receiving_report_source_locked_impl: {
        Args: { p_rr_id: string }
        Returns: string
      }
      fn_post_revenue_recognition_entry: {
        Args: { p_entry_id: string }
        Returns: string
      }
      fn_post_revenue_recognition_entry_source_locked_impl: {
        Args: { p_entry_id: string }
        Returns: string
      }
      fn_post_sales_invoice: {
        Args: { p_invoice_id: string }
        Returns: undefined
      }
      fn_post_sales_invoice_costing_legacy_20260808: {
        Args: { p_invoice_id: string }
        Returns: undefined
      }
      fn_post_stock_adjustment: {
        Args: { p_adjustment_id: string }
        Returns: string
      }
      fn_post_stock_adjustment_source_locked_impl: {
        Args: { p_adjustment_id: string }
        Returns: string
      }
      fn_post_stock_transfer: {
        Args: { p_transfer_id: string }
        Returns: string
      }
      fn_post_stock_transfer_source_locked_impl: {
        Args: { p_transfer_id: string }
        Returns: string
      }
      fn_post_vendor_bill: { Args: { p_bill_id: string }; Returns: undefined }
      fn_post_vendor_credit: { Args: { p_vc_id: string }; Returns: undefined }
      fn_post_vendor_credit_source_locked_impl: {
        Args: { p_vc_id: string }
        Returns: undefined
      }
      fn_post_vendor_credit_vat_lump_impl: {
        Args: { p_vc_id: string }
        Returns: undefined
      }
      fn_post_withholding_remittance: {
        Args: { p_id: string }
        Returns: string
      }
      fn_posting_kernel_origin: {
        Args: { p_context: string }
        Returns: boolean
      }
      fn_posting_plan_fingerprint: { Args: { p_plan: Json }; Returns: string }
      fn_preview_gl_impact: {
        Args: {
          p_posting_date?: string
          p_source_doc_id: string
          p_source_doc_type: string
        }
        Returns: Json
      }
      fn_preview_gl_impact_core: {
        Args: {
          p_posting_date?: string
          p_source_doc_id: string
          p_source_doc_type: string
        }
        Returns: Json
      }
      fn_preview_sales_invoice_gl_impact: {
        Args: { p_invoice_id: string; p_posting_date?: string }
        Returns: Json
      }
      fn_preview_sales_invoice_gl_impact_aud053_core: {
        Args: { p_invoice_id: string; p_posting_date?: string }
        Returns: Json
      }
      fn_provision_company: {
        Args: { p_idempotency_key?: string; p_request: Json }
        Returns: Json
      }
      fn_provision_company_accounting_config: {
        Args: { p_company_id: string }
        Returns: string
      }
      fn_provision_company_dimension_defaults: {
        Args: { p_company_id: string }
        Returns: number
      }
      fn_provision_company_inventory_config: {
        Args: { p_company_id: string }
        Returns: string
      }
      fn_provision_compliance_profile: {
        Args: { p_company_id: string }
        Returns: string
      }
      fn_provision_number_series: {
        Args: { p_branch_id: string; p_company_id: string }
        Returns: number
      }
      fn_provision_pxl_standard_coa: {
        Args: { p_company_id: string; p_created_by?: string }
        Returns: number
      }
      fn_qap_2307_reconciliation: {
        Args: {
          p_company_id: string
          p_tax_quarter: number
          p_tax_year: number
        }
        Returns: {
          atc_code: string
          atc_code_id: string
          base_variance: number
          form2307_status: string
          form2307_tax_base: number
          form2307_tax_withheld: number
          form2307_version: number
          is_reconciled: boolean
          nature_of_payment: string
          qap_tax_base: number
          qap_tax_withheld: number
          supplier_id: string
          supplier_name: string
          supplier_tin: string
          tax_rate: number
          withheld_variance: number
        }[]
      }
      fn_rebuild_document_vat_details: {
        Args: { p_source_doc_id: string; p_source_doc_type: string }
        Returns: undefined
      }
      fn_receive_inventory: { Args: { p_data: Json }; Returns: string }
      fn_record_form2307_received: {
        Args: {
          p_atc_code_id: string
          p_certificate_amount?: number
          p_date_received: string
          p_file_url?: string
          p_period_covered: string
          p_receipt_line_id: string
          p_remarks?: string
        }
        Returns: string
      }
      fn_record_impairment: { Args: { p_data: Json }; Returns: string }
      fn_record_posting_event: {
        Args: {
          p_company_id: string
          p_details?: Json
          p_event_type: string
          p_journal_entry_id?: string
          p_source_doc_id: string
          p_source_doc_type: string
        }
        Returns: string
      }
      fn_record_transaction_event: {
        Args: {
          p_after_status?: string
          p_before_status?: string
          p_company_id: string
          p_details?: Json
          p_event_type: string
          p_journal_entry_id?: string
          p_reason?: string
          p_source_doc_id: string
          p_source_doc_type: string
          p_source_table?: string
        }
        Returns: string
      }
      fn_register_fixed_asset: { Args: { p_data: Json }; Returns: string }
      fn_reject_approval_request: {
        Args: {
          p_current_record_version: string
          p_reason: string
          p_request_id: string
        }
        Returns: Json
      }
      fn_render_cas_dat: { Args: { p_snapshot_id: string }; Returns: Json }
      fn_render_cas_dat_text: {
        Args: {
          p_company_tin: string
          p_period_end: string
          p_period_start: string
          p_report_type: string
          p_rows: Json
          p_snapshot_version: number
        }
        Returns: string
      }
      fn_reopen_accounting_period: {
        Args: {
          p_company_id: string
          p_fiscal_period_id: string
          p_reason: string
        }
        Returns: string
      }
      fn_reopen_fiscal_year: {
        Args: {
          p_company_id: string
          p_fiscal_year_id: string
          p_reason: string
        }
        Returns: string
      }
      fn_report_gl_by_dimension: {
        Args: {
          p_company_id: string
          p_date_from?: string
          p_date_to?: string
          p_dimension: string
        }
        Returns: {
          dimension_code: string
          dimension_id: string
          dimension_name: string
          line_count: number
          net_debit: number
          total_credit: number
          total_debit: number
        }[]
      }
      fn_report_snapshot_key_uuid: { Args: { p_key: string }; Returns: string }
      fn_require_company_ewt_payable_enabled: {
        Args: { p_company_id: string; p_context?: string }
        Returns: undefined
      }
      fn_require_open_fiscal_period: {
        Args: { p_company_id: string; p_lock?: boolean; p_posting_date: string }
        Returns: string
      }
      fn_require_postable_account: {
        Args: { p_account_id: string; p_company_id: string; p_context?: string }
        Returns: undefined
      }
      fn_require_vat_registered_company: {
        Args: { p_company_id: string; p_context?: string }
        Returns: undefined
      }
      fn_required_approval_workflow: {
        Args: {
          p_amount: number
          p_company_id: string
          p_document_label: string
          p_module_type: string
        }
        Returns: string
      }
      fn_resolve_account: {
        Args: {
          p_as_of?: string
          p_company_id: string
          p_context?: Json
          p_key_code: string
        }
        Returns: string
      }
      fn_resolve_approval_rule: {
        Args: {
          p_action_type: string
          p_amount?: number
          p_as_of?: string
          p_branch_id: string
          p_company_id: string
          p_currency_code?: string
          p_document_type: string
          p_module_type: string
          p_requester_id?: string
        }
        Returns: {
          precedence: Json
          specificity_score: number
          step_count: number
          workflow_id: string
          workflow_name: string
        }[]
      }
      fn_resolve_business_tax_code: {
        Args: {
          p_as_of?: string
          p_company_id: string
          p_context?: string
          p_percentage_tax_code_id: string
          p_transaction_type?: string
          p_vat_code_id: string
        }
        Returns: Database["public"]["CompositeTypes"]["business_tax_resolution"][]
        SetofOptions: {
          from: "*"
          to: "business_tax_resolution"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      fn_resolve_comparative_period: {
        Args: {
          p_company_id: string
          p_period_end: string
          p_period_start: string
        }
        Returns: Json
      }
      fn_resolve_posting_account: {
        Args: {
          p_as_of: string
          p_company_id: string
          p_key: string
          p_unconfigured_msg: string
        }
        Returns: string
      }
      fn_resolve_posting_source: {
        Args: { p_document_type: string; p_lock?: boolean; p_source_id: string }
        Returns: Json
      }
      fn_resolve_vat_code: {
        Args: {
          p_as_of?: string
          p_company_id: string
          p_context?: string
          p_transaction_type?: string
          p_vat_code_id: string
        }
        Returns: Database["public"]["CompositeTypes"]["vat_code_resolution"]
        SetofOptions: {
          from: "*"
          to: "vat_code_resolution"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      fn_return_inventory: { Args: { p_data: Json }; Returns: Json }
      fn_reverse_inventory_issue: {
        Args: {
          p_inventory_transaction_id: string
          p_journal_entry_id: string
          p_notes?: string
          p_reference_doc_id: string
          p_reference_doc_type: string
          p_reversal_date: string
          p_source_line_id: string
        }
        Returns: string
      }
      fn_reverse_inventory_receipt: {
        Args: {
          p_inventory_transaction_id: string
          p_journal_entry_id: string
          p_notes?: string
          p_reference_doc_id: string
          p_reference_doc_type: string
          p_reversal_date: string
          p_source_line_id: string
        }
        Returns: string
      }
      fn_reverse_je: {
        Args: { p_je_id: string; p_reversal_date?: string }
        Returns: string
      }
      fn_reverse_opening_balance: {
        Args: { p_batch_id: string; p_reason: string; p_reversal_date: string }
        Returns: string
      }
      fn_reverse_posted_journal_entry: {
        Args: {
          p_description: string
          p_je_number: string
          p_original_je_id: string
          p_reference_doc_id: string
          p_reference_doc_type: string
          p_reversal_date: string
        }
        Returns: string
      }
      fn_reverse_receipt_core: {
        Args: {
          p_reason: string
          p_receipt_id: string
          p_terminal_status: string
        }
        Returns: string
      }
      fn_reverse_tax_detail_entries: {
        Args: {
          p_fiscal_period_id: string
          p_reversal_date: string
          p_source_doc_id: string
          p_source_doc_type: string
        }
        Returns: undefined
      }
      fn_reverse_vendor_credit_application: {
        Args: {
          p_application_id: string
          p_reason?: string
          p_reversal_date?: string
        }
        Returns: string
      }
      fn_revert_si_to_draft: {
        Args: { p_invoice_id: string }
        Returns: undefined
      }
      fn_revert_vendor_bill_to_draft: {
        Args: { p_bill_id: string }
        Returns: undefined
      }
      fn_role_is_privileged_maintenance: {
        Args: { p_role: unknown }
        Returns: boolean
      }
      fn_row_written_by_current_txn: {
        Args: { p_xmin_raw: number }
        Returns: boolean
      }
      fn_save_cash_purchase: {
        Args: { p_cp_id: string; p_header: Json; p_lines: Json }
        Returns: string
      }
      fn_save_cash_purchase_core_20260718: {
        Args: { p_cp_id: string; p_header: Json; p_lines: Json }
        Returns: string
      }
      fn_save_cash_sale: {
        Args: { p_cwt_amount?: number; p_header: Json; p_lines: Json }
        Returns: Json
      }
      fn_save_cash_sale_costing_legacy_20260808: {
        Args: { p_cwt_amount?: number; p_header: Json; p_lines: Json }
        Returns: Json
      }
      fn_save_credit_memo: {
        Args: {
          p_cm_id: string
          p_header: Json
          p_lines: Json
          p_next_status?: string
        }
        Returns: string
      }
      fn_save_credit_memo_inventory_legacy_20260808: {
        Args: {
          p_cm_id: string
          p_header: Json
          p_lines: Json
          p_next_status?: string
        }
        Returns: string
      }
      fn_save_debit_memo: {
        Args: {
          p_dm_id: string
          p_header: Json
          p_lines: Json
          p_next_status?: string
        }
        Returns: string
      }
      fn_save_opening_balance: {
        Args: {
          p_ap_lines?: Json
          p_ar_lines?: Json
          p_bank_lines?: Json
          p_batch_id: string
          p_gl_lines?: Json
          p_header: Json
          p_inventory_lines?: Json
        }
        Returns: string
      }
      fn_save_payment_voucher: {
        Args: { p_header: Json; p_lines: Json; p_voucher_id: string }
        Returns: string
      }
      fn_save_payment_voucher_phase3_core: {
        Args: { p_header: Json; p_lines: Json; p_voucher_id: string }
        Returns: string
      }
      fn_save_payment_voucher_pre_opening_core: {
        Args: { p_header: Json; p_lines: Json; p_voucher_id: string }
        Returns: string
      }
      fn_save_purchase_order: {
        Args: { p_header: Json; p_lines: Json; p_po_id: string }
        Returns: string
      }
      fn_save_purchase_order_core_20260718: {
        Args: { p_header: Json; p_lines: Json; p_po_id: string }
        Returns: string
      }
      fn_save_purchase_return: {
        Args: { p_header: Json; p_lines: Json; p_return_id: string }
        Returns: string
      }
      fn_save_purchase_return_inventory_legacy_20260808: {
        Args: { p_header: Json; p_lines: Json; p_return_id: string }
        Returns: string
      }
      fn_save_receipt: {
        Args: { p_header: Json; p_lines: Json; p_receipt_id: string }
        Returns: string
      }
      fn_save_receipt_pre_opening_core: {
        Args: { p_header: Json; p_lines: Json; p_receipt_id: string }
        Returns: string
      }
      fn_save_receiving_report: {
        Args: { p_header: Json; p_lines: Json; p_rr_id: string }
        Returns: string
      }
      fn_save_receiving_report_core_20260718: {
        Args: { p_header: Json; p_lines: Json; p_rr_id: string }
        Returns: string
      }
      fn_save_sales_invoice: {
        Args: { p_header: Json; p_invoice_id: string; p_lines: Json }
        Returns: string
      }
      fn_save_sales_invoice_aud053_core: {
        Args: { p_header: Json; p_invoice_id: string; p_lines: Json }
        Returns: string
      }
      fn_save_sales_invoice_inventory_legacy_20260808: {
        Args: { p_header: Json; p_invoice_id: string; p_lines: Json }
        Returns: string
      }
      fn_save_supplier_debit_memo: {
        Args: { p_header: Json; p_lines: Json; p_sdm_id: string }
        Returns: string
      }
      fn_save_vendor_bill: {
        Args: { p_bill_id: string; p_header: Json; p_lines: Json }
        Returns: string
      }
      fn_save_vendor_bill_core_20260718: {
        Args: { p_bill_id: string; p_header: Json; p_lines: Json }
        Returns: string
      }
      fn_save_vendor_credit: {
        Args: { p_header: Json; p_lines: Json; p_vc_id: string }
        Returns: string
      }
      fn_save_withholding_remittance: {
        Args: {
          p_amount: number
          p_branch_id: string
          p_company_id: string
          p_form_type: string
          p_id: string
          p_particulars: string
          p_period_month: number
          p_period_quarter: number
          p_period_year: number
          p_reference_no: string
          p_remittance_date: string
          p_remittance_kind: string
          p_remittance_number: string
          p_settlement_account_id: string
        }
        Returns: string
      }
      fn_seed_company_coa: {
        Args: { p_company_id: string; p_template_code?: string }
        Returns: number
      }
      fn_seed_company_fs_structure: {
        Args: { p_company_id: string }
        Returns: number
      }
      fn_seed_company_percentage_tax_codes: {
        Args: { p_company_id: string }
        Returns: number
      }
      fn_seed_company_uom: { Args: { p_company_id: string }; Returns: number }
      fn_send_supplier_debit_memo: {
        Args: { p_sdm_id: string }
        Returns: undefined
      }
      fn_ship_purchase_return: {
        Args: { p_return_id: string }
        Returns: undefined
      }
      fn_snapshot_books_export: {
        Args: {
          p_book_type: string
          p_company_id: string
          p_date_from: string
          p_date_to: string
          p_file_name: string
        }
        Returns: Json
      }
      fn_snapshot_cas_audit_package: {
        Args: {
          p_company_id: string
          p_date_from: string
          p_date_to: string
          p_file_name: string
        }
        Returns: Json
      }
      fn_snapshot_cas_export: {
        Args: {
          p_company_id: string
          p_file_name: string
          p_month: number
          p_report_type: string
          p_year: number
        }
        Returns: Json
      }
      fn_snapshot_cas_export_unchecked: {
        Args: {
          p_company_id: string
          p_file_name: string
          p_month: number
          p_report_type: string
          p_year: number
        }
        Returns: Json
      }
      fn_snapshot_filing_artifact_export: {
        Args: {
          p_company_id: string
          p_form_code: string
          p_format?: string
          p_period: number
          p_year: number
        }
        Returns: string
      }
      fn_snapshot_vat_export: {
        Args: {
          p_company_id: string
          p_export_part?: string
          p_month: number
          p_report_type: string
          p_year: number
        }
        Returns: string
      }
      fn_snapshot_vat_export_unchecked: {
        Args: {
          p_company_id: string
          p_export_part?: string
          p_month: number
          p_report_type: string
          p_year: number
        }
        Returns: string
      }
      fn_stamp_void_inventory_dimensions: {
        Args: { p_invoice_id: string }
        Returns: undefined
      }
      fn_submit_approval_request: {
        Args: {
          p_action_type: string
          p_branch_id: string
          p_company_id: string
          p_currency_code?: string
          p_document_type: string
          p_module_type: string
          p_record_snapshot?: Json
          p_record_version: string
          p_request_reason?: string
          p_source_document_amount?: number
          p_source_document_id: string
          p_source_document_no: string
        }
        Returns: Json
      }
      fn_supersede_form_2307_issued: {
        Args: { p_issuance_id: string; p_reason?: string }
        Returns: string
      }
      fn_supplier_ledger_asof: {
        Args: { p_as_of: string; p_company_id: string; p_supplier_id?: string }
        Returns: {
          company_id: string
          created_at: string
          credit_amount: number
          debit_amount: number
          description: string
          document_id: string
          document_number: string
          document_type: string
          external_ref: string
          running_balance: number
          source_doc_id: string
          source_doc_type: string
          supplier_id: string
          supplier_name: string
          transaction_date: string
        }[]
      }
      fn_sync_account_mapping_from_config: {
        Args: { p_company_id: string }
        Returns: number
      }
      fn_sync_coa_control_accounts: {
        Args: { p_company_id: string }
        Returns: number
      }
      fn_tax_code_is_current: {
        Args: { p_as_of?: string; p_tax_code_id: string }
        Returns: boolean
      }
      fn_tax_code_set_active: {
        Args: { p_id: string; p_is_active: boolean; p_reason?: string }
        Returns: undefined
      }
      fn_tax_code_succeed: {
        Args: {
          p_description?: string
          p_effective_from: string
          p_gl_account_id?: string
          p_id: string
          p_rate: number
          p_reason?: string
        }
        Returns: string
      }
      fn_tax_code_upsert: {
        Args: {
          p_code: string
          p_description: string
          p_effective_from?: string
          p_effective_to?: string
          p_gl_account_id?: string
          p_id?: string
          p_is_active?: boolean
          p_rate: number
          p_reason?: string
          p_supersedes_id?: string
          p_tax_type: string
        }
        Returns: string
      }
      fn_tax_code_used: { Args: { p_tax_code_id: string }; Returns: boolean }
      fn_tax_code_version_asof: {
        Args: { p_as_of?: string; p_code: string }
        Returns: string
      }
      fn_tax_ledger_gl_reconciliation: {
        Args: {
          p_company_id: string
          p_date_from: string
          p_date_to: string
          p_tax_kinds: string[]
        }
        Returns: {
          gl_account_code: string
          gl_account_id: string
          gl_account_name: string
          gl_amount: number
          is_reconciled: boolean
          ledger_tax_amount: number
          ledger_tax_base: number
          tax_kind: string
          variance: number
        }[]
      }
      fn_tax_reference_asof: {
        Args: {
          p_as_of?: string
          p_code: string
          p_reference_type: string
          p_tax_category?: string
        }
        Returns: string
      }
      fn_transaction_actor_role: { Args: never; Returns: string }
      fn_transaction_event_type_for_status: {
        Args: { p_after_status: string; p_before_status: string }
        Returns: string
      }
      fn_transfer_fixed_asset: { Args: { p_data: Json }; Returns: string }
      fn_transfer_inventory: { Args: { p_data: Json }; Returns: Json }
      fn_transition_account_lifecycle: {
        Args: { p_account_id: string; p_new_status: string; p_reason?: string }
        Returns: {
          account_code: string
          account_name: string
          account_type: string
          allow_subledger: boolean
          cash_flow_category: string | null
          company_id: string
          cost_behavior: string | null
          created_at: string | null
          created_by: string | null
          currency_code: string | null
          effective_from: string | null
          effective_to: string | null
          fs_group: string | null
          fs_statement: string | null
          fs_subgroup: string | null
          id: string
          is_active: boolean | null
          is_capitalizable: boolean
          is_cash_equivalent: boolean
          is_control_account: boolean
          is_operating_expense: boolean
          is_postable: boolean | null
          is_tax_account: boolean
          lifecycle_status: string
          normal_balance: string
          parent_id: string | null
          subledger_type: string | null
          updated_at: string | null
          updated_by: string | null
        }
        SetofOptions: {
          from: "*"
          to: "chart_of_accounts"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      fn_trial_balance_report: {
        Args: {
          p_account_id?: string
          p_company_id: string
          p_date_from: string
          p_date_to: string
          p_entry_classes?: string[]
          p_include_zero?: boolean
        }
        Returns: {
          account_code: string
          account_id: string
          account_name: string
          account_type: string
          closing_net: number
          normal_balance: string
          opening_net: number
          period_credit: number
          period_debit: number
        }[]
      }
      fn_twa_ewt_atc_asof: {
        Args: { p_document_date?: string; p_line_kind: string }
        Returns: string
      }
      fn_update_form_2307_issued_status: {
        Args: {
          p_action_date?: string
          p_issuance_id: string
          p_status: string
        }
        Returns: string
      }
      fn_update_payment_tracking: {
        Args: {
          p_action: string
          p_date?: string
          p_remarks?: string
          p_voucher_id: string
        }
        Returns: undefined
      }
      fn_update_wac: {
        Args: {
          p_item_id: string
          p_qty_in: number
          p_unit_cost_in: number
          p_warehouse_id: string
        }
        Returns: undefined
      }
      fn_validate_cash_purchase_ewt_ready: {
        Args: { p_cp_id: string }
        Returns: undefined
      }
      fn_validate_company_accounting_config: {
        Args: { p_company_id: string }
        Returns: {
          check_code: string
          detail: string
        }[]
      }
      fn_validate_company_inventory_config: {
        Args: { p_company_id: string }
        Returns: {
          check_code: string
          detail: string
        }[]
      }
      fn_validate_company_provisioning: {
        Args: { p_request: Json }
        Returns: {
          check_code: string
          detail: string
          error_order: number
          field_name: string
        }[]
      }
      fn_validate_company_vat_amount: {
        Args: { p_company_id: string; p_context?: string; p_vat_amount: number }
        Returns: undefined
      }
      fn_validate_company_vat_code: {
        Args: {
          p_as_of?: string
          p_company_id: string
          p_context?: string
          p_transaction_type: string
          p_vat_code_id: string
        }
        Returns: undefined
      }
      fn_validate_document_vat_registration: {
        Args: {
          p_as_of?: string
          p_company_id: string
          p_context: string
          p_document_id: string
          p_header_vat_amount: number
          p_line_table: unknown
          p_line_vat_amount_column: unknown
          p_parent_column: unknown
          p_transaction_type: string
        }
        Returns: undefined
      }
      fn_validate_form2307_received_tracking: {
        Args: {
          p_atc_code_id: string
          p_claim_tax_quarter: number
          p_claim_tax_year: number
          p_company_id: string
          p_cwt_amount_booked: number
          p_date_received: string
          p_period_covered: string
          p_receipt_line_id: string
          p_status: string
        }
        Returns: undefined
      }
      fn_validate_invoice_posting_totals: {
        Args: { p_document_type: string; p_source_id: string }
        Returns: undefined
      }
      fn_validate_master_data_import: {
        Args: {
          p_company_id: string
          p_master_key: string
          p_options?: Json
          p_rows: Json
        }
        Returns: Json
      }
      fn_validate_payment_voucher_ewt_ready: {
        Args: { p_voucher_id: string }
        Returns: undefined
      }
      fn_validate_payment_voucher_line_ewt: {
        Args: {
          p_atc_code_id: string
          p_company_id: string
          p_document_date?: string
          p_ewt_amount: number
          p_ewt_tax_base?: number
          p_ewt_variance_reason?: string
          p_payment_amount: number
        }
        Returns: undefined
      }
      fn_validate_posting_plan: { Args: { p_plan: Json }; Returns: boolean }
      fn_validate_purchase_dimensions: {
        Args: {
          p_branch_id: string
          p_company_id: string
          p_cost_center_id: string
          p_department_id: string
          p_warehouse_id: string
        }
        Returns: undefined
      }
      fn_validate_receipt_cwt_ready: {
        Args: { p_receipt_id: string }
        Returns: undefined
      }
      fn_validate_receipt_line_cwt: {
        Args: {
          p_atc_code_id: string
          p_company_id: string
          p_cwt_amount: number
          p_cwt_source?: string
          p_cwt_tax_base?: number
          p_cwt_variance_reason?: string
          p_document_date?: string
          p_invoice_id?: string
          p_payment_amount: number
        }
        Returns: undefined
      }
      fn_validate_sales_invoice_accounting_ready: {
        Args: { p_invoice_id: string }
        Returns: undefined
      }
      fn_validate_sales_invoice_accounting_ready_aud053_core: {
        Args: { p_invoice_id: string }
        Returns: undefined
      }
      fn_validate_sales_invoice_vat_registration: {
        Args: { p_invoice_id: string }
        Returns: undefined
      }
      fn_validate_settlement_posting: {
        Args: { p_document_type: string; p_source_id: string }
        Returns: undefined
      }
      fn_validate_vendor_bill_accounting_ready: {
        Args: { p_bill_id: string }
        Returns: undefined
      }
      fn_validate_vendor_bill_vat_registration: {
        Args: { p_bill_id: string }
        Returns: undefined
      }
      fn_vat_code_set_active: {
        Args: { p_id: string; p_is_active: boolean; p_reason?: string }
        Returns: undefined
      }
      fn_vat_code_succeed: {
        Args: {
          p_description?: string
          p_effective_from: string
          p_id: string
          p_reason?: string
          p_relief_category?: string
          p_tax_code_id: string
        }
        Returns: string
      }
      fn_vat_code_upsert: {
        Args: {
          p_description: string
          p_effective_from?: string
          p_effective_to?: string
          p_id?: string
          p_is_active?: boolean
          p_reason?: string
          p_relief_category?: string
          p_supersedes_id?: string
          p_tax_code_id: string
          p_transaction_type: string
          p_vat_classification: string
          p_vat_code: string
        }
        Returns: string
      }
      fn_vat_code_used: { Args: { p_vat_code_id: string }; Returns: boolean }
      fn_vat_codes_asof: {
        Args: {
          p_as_of?: string
          p_company_id: string
          p_transaction_type?: string
        }
        Returns: {
          description: string
          effective_from: string
          effective_to: string
          id: string
          rate: number
          tax_code_id: string
          transaction_type: string
          vat_classification: string
          vat_code: string
        }[]
      }
      fn_vat_gl_reconciliation: {
        Args: { p_company_id: string; p_date_from: string; p_date_to: string }
        Returns: {
          gl_account_code: string
          gl_account_id: string
          gl_account_name: string
          gl_amount: number
          is_reconciled: boolean
          ledger_tax_amount: number
          ledger_tax_base: number
          tax_kind: string
          variance: number
        }[]
      }
      fn_vat_return_period_bounds: {
        Args: {
          p_month: number
          p_quarter: number
          p_return_type: string
          p_year: number
        }
        Returns: Record<string, unknown>
      }
      fn_vat_return_report_payload: {
        Args: { p_return: Database["public"]["Tables"]["vat_returns"]["Row"] }
        Returns: Json
      }
      fn_vendor_bill_accrued_ewt_amount: {
        Args: { p_bill_id: string }
        Returns: number
      }
      fn_vendor_bill_has_accrued_ewt: {
        Args: { p_bill_id: string }
        Returns: boolean
      }
      fn_void_cash_sale: {
        Args: {
          p_invoice_id: string
          p_memo?: string
          p_void_reason_id: string
        }
        Returns: undefined
      }
      fn_void_delivery_receipt: {
        Args: { p_dr_id: string; p_memo?: string; p_void_reason_id: string }
        Returns: undefined
      }
      fn_void_delivery_receipt_costing_legacy_20260808: {
        Args: { p_dr_id: string; p_memo?: string; p_void_reason_id: string }
        Returns: undefined
      }
      fn_void_receiving_report: {
        Args: { p_memo?: string; p_rr_id: string; p_void_reason_id: string }
        Returns: undefined
      }
      fn_void_sales_invoice: {
        Args: {
          p_invoice_id: string
          p_memo?: string
          p_void_reason_id: string
        }
        Returns: undefined
      }
      fn_void_sales_invoice_aud053_core: {
        Args: {
          p_invoice_id: string
          p_memo?: string
          p_void_reason_id: string
        }
        Returns: undefined
      }
      fn_void_sales_invoice_costing_legacy_20260808: {
        Args: {
          p_invoice_id: string
          p_memo?: string
          p_void_reason_id: string
        }
        Returns: undefined
      }
      fn_void_vendor_bill: {
        Args: { p_bill_id: string; p_memo?: string; p_void_reason_id: string }
        Returns: undefined
      }
      fn_void_withholding_remittance: {
        Args: { p_id: string; p_reason: string }
        Returns: string
      }
      fn_wht_gl_reconciliation: {
        Args: { p_company_id: string; p_date_from: string; p_date_to: string }
        Returns: {
          gl_account_code: string
          gl_account_id: string
          gl_account_name: string
          gl_amount: number
          is_reconciled: boolean
          ledger_tax_amount: number
          ledger_tax_base: number
          tax_kind: string
          variance: number
        }[]
      }
      fn_withdraw_approval_request: {
        Args: { p_reason?: string; p_request_id: string }
        Returns: Json
      }
      is_any_company_admin: { Args: never; Returns: boolean }
      is_company_member: { Args: { p_company_id: string }; Returns: boolean }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      business_tax_resolution: {
        tax_family: string | null
        code_id: string | null
        code: string | null
        description: string | null
        tax_code_id: string | null
        tax_code: string | null
        classification: string | null
        transaction_type: string | null
        tax_rate: number | null
        atc_code_id: string | null
        atc_code: string | null
        form_type: string | null
        effective_from: string | null
        effective_to: string | null
      }
      tax_component: {
        tax_kind: string | null
        vat_code_id: string | null
        tax_code_id: string | null
        atc_code_id: string | null
        atc_code: string | null
        atc_description: string | null
        classification: string | null
        tax_base: number | null
        tax_rate: number | null
        tax_amount: number | null
        net_amount: number | null
        gross_amount: number | null
        price_basis: string | null
      }
      vat_code_resolution: {
        vat_code_id: string | null
        vat_code: string | null
        tax_code_id: string | null
        tax_code: string | null
        classification: string | null
        transaction_type: string | null
        vat_rate: number | null
        effective_from: string | null
        effective_to: string | null
      }
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {},
  },
} as const
