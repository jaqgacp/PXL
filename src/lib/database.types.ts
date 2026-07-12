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
          company_id: string
          created_at: string | null
          created_by: string | null
          escalated_at: string | null
          id: string
          remarks: string | null
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
          company_id: string
          created_at?: string | null
          created_by?: string | null
          escalated_at?: string | null
          id?: string
          remarks?: string | null
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
          company_id?: string
          created_at?: string | null
          created_by?: string | null
          escalated_at?: string | null
          id?: string
          remarks?: string | null
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
      approval_workflow_steps: {
        Row: {
          action_required: string
          approver_role_id: string | null
          approver_type: string
          approver_user_id: string | null
          company_id: string
          created_at: string | null
          escalation_hours: number | null
          id: string
          step_sequence: number
          workflow_id: string
        }
        Insert: {
          action_required?: string
          approver_role_id?: string | null
          approver_type: string
          approver_user_id?: string | null
          company_id: string
          created_at?: string | null
          escalation_hours?: number | null
          id?: string
          step_sequence: number
          workflow_id: string
        }
        Update: {
          action_required?: string
          approver_role_id?: string | null
          approver_type?: string
          approver_user_id?: string | null
          company_id?: string
          created_at?: string | null
          escalation_hours?: number | null
          id?: string
          step_sequence?: number
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
          company_id: string
          created_at: string | null
          created_by: string | null
          document_type: string
          id: string
          is_active: boolean | null
          module_type: string
          threshold_value: number | null
          trigger_condition_type: string
          updated_at: string | null
          updated_by: string | null
          workflow_name: string
        }
        Insert: {
          company_id: string
          created_at?: string | null
          created_by?: string | null
          document_type: string
          id?: string
          is_active?: boolean | null
          module_type: string
          threshold_value?: number | null
          trigger_condition_type: string
          updated_at?: string | null
          updated_by?: string | null
          workflow_name: string
        }
        Update: {
          company_id?: string
          created_at?: string | null
          created_by?: string | null
          document_type?: string
          id?: string
          is_active?: boolean | null
          module_type?: string
          threshold_value?: number | null
          trigger_condition_type?: string
          updated_at?: string | null
          updated_by?: string | null
          workflow_name?: string
        }
        Relationships: [
          {
            foreignKeyName: "approval_workflows_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
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
        ]
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
      cas_export_log: {
        Row: {
          company_id: string
          export_type: string
          file_name: string
          generated_at: string
          generated_by: string | null
          id: string
          period_month: number | null
          period_quarter: number | null
          period_year: number | null
          remarks: string | null
          report_name: string
          row_count: number
          snapshot_id: string | null
        }
        Insert: {
          company_id: string
          export_type: string
          file_name: string
          generated_at?: string
          generated_by?: string | null
          id?: string
          period_month?: number | null
          period_quarter?: number | null
          period_year?: number | null
          remarks?: string | null
          report_name: string
          row_count?: number
          snapshot_id?: string | null
        }
        Update: {
          company_id?: string
          export_type?: string
          file_name?: string
          generated_at?: string
          generated_by?: string | null
          id?: string
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
            foreignKeyName: "cas_export_log_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
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
        }
        Insert: {
          company_id: string
          cp_id: string
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
        }
        Update: {
          company_id?: string
          cp_id?: string
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
            foreignKeyName: "cash_purchase_lines_cp_id_fkey"
            columns: ["cp_id"]
            isOneToOne: false
            referencedRelation: "cash_purchases"
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
        ]
      }
      cash_purchases: {
        Row: {
          branch_id: string | null
          company_id: string
          cp_number: string
          created_at: string
          created_by: string | null
          fiscal_period_id: string | null
          id: string
          journal_entry_id: string | null
          payment_account_id: string | null
          payment_method: string
          posted_at: string | null
          posted_by: string | null
          reference_number: string | null
          remarks: string | null
          status: string
          supplier_id: string | null
          supplier_name_snapshot: string | null
          supplier_tin_snapshot: string | null
          total_amount: number
          total_exempt_amount: number
          total_input_vat_amount: number
          total_taxable_amount: number
          total_zero_rated_amount: number
          transaction_date: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          branch_id?: string | null
          company_id: string
          cp_number: string
          created_at?: string
          created_by?: string | null
          fiscal_period_id?: string | null
          id?: string
          journal_entry_id?: string | null
          payment_account_id?: string | null
          payment_method?: string
          posted_at?: string | null
          posted_by?: string | null
          reference_number?: string | null
          remarks?: string | null
          status?: string
          supplier_id?: string | null
          supplier_name_snapshot?: string | null
          supplier_tin_snapshot?: string | null
          total_amount?: number
          total_exempt_amount?: number
          total_input_vat_amount?: number
          total_taxable_amount?: number
          total_zero_rated_amount?: number
          transaction_date: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          branch_id?: string | null
          company_id?: string
          cp_number?: string
          created_at?: string
          created_by?: string | null
          fiscal_period_id?: string | null
          id?: string
          journal_entry_id?: string | null
          payment_account_id?: string | null
          payment_method?: string
          posted_at?: string | null
          posted_by?: string | null
          reference_number?: string | null
          remarks?: string | null
          status?: string
          supplier_id?: string | null
          supplier_name_snapshot?: string | null
          supplier_tin_snapshot?: string | null
          total_amount?: number
          total_exempt_amount?: number
          total_input_vat_amount?: number
          total_taxable_amount?: number
          total_zero_rated_amount?: number
          transaction_date?: string
          updated_at?: string
          updated_by?: string | null
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
            foreignKeyName: "cash_purchases_fiscal_period_id_fkey"
            columns: ["fiscal_period_id"]
            isOneToOne: false
            referencedRelation: "fiscal_periods"
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
            foreignKeyName: "cash_purchases_payment_account_id_fkey"
            columns: ["payment_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_purchases_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
      chart_of_accounts: {
        Row: {
          account_code: string
          account_name: string
          account_type: string
          company_id: string
          created_at: string | null
          created_by: string | null
          currency_code: string | null
          id: string
          is_active: boolean | null
          is_postable: boolean | null
          normal_balance: string
          parent_id: string | null
          updated_at: string | null
          updated_by: string | null
        }
        Insert: {
          account_code: string
          account_name: string
          account_type: string
          company_id: string
          created_at?: string | null
          created_by?: string | null
          currency_code?: string | null
          id?: string
          is_active?: boolean | null
          is_postable?: boolean | null
          normal_balance: string
          parent_id?: string | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Update: {
          account_code?: string
          account_name?: string
          account_type?: string
          company_id?: string
          created_at?: string | null
          created_by?: string | null
          currency_code?: string | null
          id?: string
          is_active?: boolean | null
          is_postable?: boolean | null
          normal_balance?: string
          parent_id?: string | null
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
      companies: {
        Row: {
          accounting_period: string
          address_line_1: string
          address_line_2: string
          bir_reg_date: string | null
          cas_date_issued: string | null
          cas_permit_no: string | null
          city: string
          created_at: string | null
          created_by: string | null
          email: string
          entity_type: string
          fiscal_start_month: number | null
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
          sec_dti_reg_date: string | null
          signatory_name: string
          signatory_position: string
          signatory_tin: string | null
          tax_registration: string
          tin: string
          trade_name: string | null
          updated_at: string | null
          updated_by: string | null
          zip_code: string
        }
        Insert: {
          accounting_period: string
          address_line_1: string
          address_line_2: string
          bir_reg_date?: string | null
          cas_date_issued?: string | null
          cas_permit_no?: string | null
          city: string
          created_at?: string | null
          created_by?: string | null
          email: string
          entity_type: string
          fiscal_start_month?: number | null
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
          sec_dti_reg_date?: string | null
          signatory_name: string
          signatory_position: string
          signatory_tin?: string | null
          tax_registration: string
          tin: string
          trade_name?: string | null
          updated_at?: string | null
          updated_by?: string | null
          zip_code: string
        }
        Update: {
          accounting_period?: string
          address_line_1?: string
          address_line_2?: string
          bir_reg_date?: string | null
          cas_date_issued?: string | null
          cas_permit_no?: string | null
          city?: string
          created_at?: string | null
          created_by?: string | null
          email?: string
          entity_type?: string
          fiscal_start_month?: number | null
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
          sec_dti_reg_date?: string | null
          signatory_name?: string
          signatory_position?: string
          signatory_tin?: string | null
          tax_registration?: string
          tin?: string
          trade_name?: string | null
          updated_at?: string | null
          updated_by?: string | null
          zip_code?: string
        }
        Relationships: [
          {
            foreignKeyName: "companies_parent_company_id_fkey"
            columns: ["parent_company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "companies_rdo_id_fkey"
            columns: ["rdo_id"]
            isOneToOne: false
            referencedRelation: "ref_rdo_codes"
            referencedColumns: ["id"]
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
          default_cash_account_id: string | null
          ewt_payable_account_id: string | null
          ewt_withheld_account_id: string | null
          id: string
          input_vat_account_id: string | null
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
          default_cash_account_id?: string | null
          ewt_payable_account_id?: string | null
          ewt_withheld_account_id?: string | null
          id?: string
          input_vat_account_id?: string | null
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
          default_cash_account_id?: string | null
          ewt_payable_account_id?: string | null
          ewt_withheld_account_id?: string | null
          id?: string
          input_vat_account_id?: string | null
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
            foreignKeyName: "company_accounting_config_vat_payable_account_id_fkey"
            columns: ["vat_payable_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      compliance_1601eq_working_papers_headers: {
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
            foreignKeyName: "compliance_1601eq_working_papers_headers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
        ]
      }
      compliance_1601eq_working_papers_lines: {
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
            foreignKeyName: "compliance_1601eq_working_papers_lines_header_id_fkey"
            columns: ["header_id"]
            isOneToOne: false
            referencedRelation: "compliance_1601eq_working_papers_headers"
            referencedColumns: ["id"]
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
      compliance_ewt_working_papers_headers: {
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
            foreignKeyName: "compliance_ewt_working_papers_headers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
        ]
      }
      compliance_ewt_working_papers_lines: {
        Row: {
          amount: number
          created_at: string
          created_by: string | null
          header_id: string
          id: string
          reference: string | null
          remarks: string | null
          transaction_id: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          amount?: number
          created_at?: string
          created_by?: string | null
          header_id: string
          id?: string
          reference?: string | null
          remarks?: string | null
          transaction_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          amount?: number
          created_at?: string
          created_by?: string | null
          header_id?: string
          id?: string
          reference?: string | null
          remarks?: string | null
          transaction_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "compliance_ewt_working_papers_lines_header_id_fkey"
            columns: ["header_id"]
            isOneToOne: false
            referencedRelation: "compliance_ewt_working_papers_headers"
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
        ]
      }
      compliance_pt_working_papers_headers: {
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
            foreignKeyName: "compliance_pt_working_papers_headers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
        ]
      }
      compliance_pt_working_papers_lines: {
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
            foreignKeyName: "compliance_pt_working_papers_lines_header_id_fkey"
            columns: ["header_id"]
            isOneToOne: false
            referencedRelation: "compliance_pt_working_papers_headers"
            referencedColumns: ["id"]
          },
        ]
      }
      compliance_vat_working_papers_headers: {
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
            foreignKeyName: "compliance_vat_working_papers_headers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
        ]
      }
      compliance_vat_working_papers_lines: {
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
            foreignKeyName: "compliance_vat_working_papers_lines_header_id_fkey"
            columns: ["header_id"]
            isOneToOne: false
            referencedRelation: "compliance_vat_working_papers_headers"
            referencedColumns: ["id"]
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
          invoice_line_id: string | null
          item_id: string | null
          line_number: number
          net_amount: number
          quantity: number
          revenue_account_id: string | null
          total_amount: number
          unit_price: number
          updated_at: string
          updated_by: string | null
          vat_amount: number
          vat_code_id: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          credit_memo_id: string
          description: string
          id?: string
          invoice_line_id?: string | null
          item_id?: string | null
          line_number?: number
          net_amount?: number
          quantity?: number
          revenue_account_id?: string | null
          total_amount?: number
          unit_price?: number
          updated_at?: string
          updated_by?: string | null
          vat_amount?: number
          vat_code_id?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          credit_memo_id?: string
          description?: string
          id?: string
          invoice_line_id?: string | null
          item_id?: string | null
          line_number?: number
          net_amount?: number
          quantity?: number
          revenue_account_id?: string | null
          total_amount?: number
          unit_price?: number
          updated_at?: string
          updated_by?: string | null
          vat_amount?: number
          vat_code_id?: string | null
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
          default_currency_id: string | null
          default_cwt_atc_code_id: string | null
          default_ewt_code_id: string | null
          default_gl_account_id: string | null
          default_tax_type: string
          default_terms_id: string | null
          delivery_address: string
          email: string | null
          id: string
          is_active: boolean | null
          is_subject_to_cwt: boolean
          is_withholding_agent: boolean
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
          default_currency_id?: string | null
          default_cwt_atc_code_id?: string | null
          default_ewt_code_id?: string | null
          default_gl_account_id?: string | null
          default_tax_type?: string
          default_terms_id?: string | null
          delivery_address: string
          email?: string | null
          id?: string
          is_active?: boolean | null
          is_subject_to_cwt?: boolean
          is_withholding_agent?: boolean
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
          default_currency_id?: string | null
          default_cwt_atc_code_id?: string | null
          default_ewt_code_id?: string | null
          default_gl_account_id?: string | null
          default_tax_type?: string
          default_terms_id?: string | null
          delivery_address?: string
          email?: string | null
          id?: string
          is_active?: boolean | null
          is_subject_to_cwt?: boolean
          is_withholding_agent?: boolean
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
            foreignKeyName: "customers_default_ewt_code_id_fkey"
            columns: ["default_ewt_code_id"]
            isOneToOne: false
            referencedRelation: "ewt_codes"
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
          item_id: string | null
          line_number: number
          lot_serial_no: string | null
          quantity: number
          so_line_id: string | null
          uom_id: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          description: string
          dr_id: string
          id?: string
          item_id?: string | null
          line_number?: number
          lot_serial_no?: string | null
          quantity?: number
          so_line_id?: string | null
          uom_id?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          description?: string
          dr_id?: string
          id?: string
          item_id?: string | null
          line_number?: number
          lot_serial_no?: string | null
          quantity?: number
          so_line_id?: string | null
          uom_id?: string | null
          updated_at?: string
          updated_by?: string | null
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
            foreignKeyName: "delivery_receipt_lines_dr_id_fkey"
            columns: ["dr_id"]
            isOneToOne: false
            referencedRelation: "delivery_receipts"
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
          sales_order_id: string | null
          shipping_method: string
          status: string
          tracking_number: string | null
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
          delivered_at?: string | null
          delivery_address?: string
          dr_date?: string
          dr_number: string
          driver_name?: string | null
          id?: string
          sales_order_id?: string | null
          shipping_method?: string
          status?: string
          tracking_number?: string | null
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
          delivered_at?: string | null
          delivery_address?: string
          dr_date?: string
          dr_number?: string
          driver_name?: string | null
          id?: string
          sales_order_id?: string | null
          shipping_method?: string
          status?: string
          tracking_number?: string | null
          updated_at?: string
          updated_by?: string | null
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
            foreignKeyName: "delivery_receipts_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "delivery_receipts_sales_order_id_fkey"
            columns: ["sales_order_id"]
            isOneToOne: false
            referencedRelation: "sales_orders"
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
            foreignKeyName: "employees_department_id_fkey"
            columns: ["department_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
        ]
      }
      ewt_codes: {
        Row: {
          atc_id: string
          company_id: string
          created_at: string | null
          created_by: string | null
          description: string
          ewt_code: string
          form_type: string
          id: string
          is_active: boolean | null
          rate: number
          tax_code_id: string
          updated_at: string | null
          updated_by: string | null
        }
        Insert: {
          atc_id: string
          company_id: string
          created_at?: string | null
          created_by?: string | null
          description: string
          ewt_code: string
          form_type: string
          id?: string
          is_active?: boolean | null
          rate: number
          tax_code_id: string
          updated_at?: string | null
          updated_by?: string | null
        }
        Update: {
          atc_id?: string
          company_id?: string
          created_at?: string | null
          created_by?: string | null
          description?: string
          ewt_code?: string
          form_type?: string
          id?: string
          is_active?: boolean | null
          rate?: number
          tax_code_id?: string
          updated_at?: string | null
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ewt_codes_atc_id_fkey"
            columns: ["atc_id"]
            isOneToOne: false
            referencedRelation: "atc_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ewt_codes_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ewt_codes_tax_code_id_fkey"
            columns: ["tax_code_id"]
            isOneToOne: false
            referencedRelation: "tax_codes"
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
            foreignKeyName: "exchange_rates_currency_id_fkey"
            columns: ["currency_id"]
            isOneToOne: false
            referencedRelation: "currencies"
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
          created_at: string
          created_by: string | null
          department_id: string | null
          depreciation_method: string
          depreciation_start_date: string
          description: string | null
          disposed_at: string | null
          fiscal_period_id: string | null
          id: string
          location: string | null
          notes: string | null
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
          created_at?: string
          created_by?: string | null
          department_id?: string | null
          depreciation_method: string
          depreciation_start_date: string
          description?: string | null
          disposed_at?: string | null
          fiscal_period_id?: string | null
          id?: string
          location?: string | null
          notes?: string | null
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
          created_at?: string
          created_by?: string | null
          department_id?: string | null
          depreciation_method?: string
          depreciation_start_date?: string
          description?: string | null
          disposed_at?: string | null
          fiscal_period_id?: string | null
          id?: string
          location?: string | null
          notes?: string | null
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
          status: string
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
          status?: string
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
          status?: string
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
          company_id: string
          created_at: string
          created_by: string | null
          customer_id: string | null
          cwt_amount_booked: number
          date_received: string | null
          file_url: string | null
          id: string
          period_covered: string | null
          receipt_line_id: string
          remarks: string | null
          status: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          atc_code_id?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          customer_id?: string | null
          cwt_amount_booked?: number
          date_received?: string | null
          file_url?: string | null
          id?: string
          period_covered?: string | null
          receipt_line_id: string
          remarks?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          atc_code_id?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          customer_id?: string | null
          cwt_amount_booked?: number
          date_received?: string | null
          file_url?: string | null
          id?: string
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
      fwt_codes: {
        Row: {
          atc_id: string
          company_id: string
          created_at: string | null
          created_by: string | null
          description: string
          form_type: string
          fwt_code: string
          id: string
          is_active: boolean | null
          rate: number
          tax_code_id: string
          updated_at: string | null
          updated_by: string | null
        }
        Insert: {
          atc_id: string
          company_id: string
          created_at?: string | null
          created_by?: string | null
          description: string
          form_type?: string
          fwt_code: string
          id?: string
          is_active?: boolean | null
          rate: number
          tax_code_id: string
          updated_at?: string | null
          updated_by?: string | null
        }
        Update: {
          atc_id?: string
          company_id?: string
          created_at?: string | null
          created_by?: string | null
          description?: string
          form_type?: string
          fwt_code?: string
          id?: string
          is_active?: boolean | null
          rate?: number
          tax_code_id?: string
          updated_at?: string | null
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fwt_codes_atc_id_fkey"
            columns: ["atc_id"]
            isOneToOne: false
            referencedRelation: "atc_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fwt_codes_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fwt_codes_tax_code_id_fkey"
            columns: ["tax_code_id"]
            isOneToOne: false
            referencedRelation: "tax_codes"
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
        ]
      }
      goods_issue_lines: {
        Row: {
          company_id: string
          gl_expense_account_id: string | null
          id: string
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
            foreignKeyName: "goods_issue_lines_gl_expense_account_id_fkey"
            columns: ["gl_expense_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
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
          created_at: string
          created_by: string | null
          department_id: string | null
          fiscal_period_id: string | null
          id: string
          issue_date: string
          issue_number: string
          journal_entry_id: string | null
          notes: string | null
          posted_at: string | null
          posted_by: string | null
          purpose: string | null
          status: string
          updated_at: string
          updated_by: string | null
          warehouse_id: string
        }
        Insert: {
          branch_id?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          department_id?: string | null
          fiscal_period_id?: string | null
          id?: string
          issue_date: string
          issue_number: string
          journal_entry_id?: string | null
          notes?: string | null
          posted_at?: string | null
          posted_by?: string | null
          purpose?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
          warehouse_id: string
        }
        Update: {
          branch_id?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          department_id?: string | null
          fiscal_period_id?: string | null
          id?: string
          issue_date?: string
          issue_number?: string
          journal_entry_id?: string | null
          notes?: string | null
          posted_at?: string | null
          posted_by?: string | null
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
            foreignKeyName: "goods_issues_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
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
      inventory_cost_layers: {
        Row: {
          company_id: string
          created_at: string
          id: string
          is_exhausted: boolean
          item_id: string
          layer_date: string
          lot_number: string | null
          original_qty: number
          qty_remaining: number
          reference_doc_id: string | null
          reference_doc_type: string | null
          serial_number: string | null
          unit_cost: number
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
          original_qty: number
          qty_remaining: number
          reference_doc_id?: string | null
          reference_doc_type?: string | null
          serial_number?: string | null
          unit_cost?: number
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
          original_qty?: number
          qty_remaining?: number
          reference_doc_id?: string | null
          reference_doc_type?: string | null
          serial_number?: string | null
          unit_cost?: number
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
            foreignKeyName: "inventory_cost_layers_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
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
      inventory_transactions: {
        Row: {
          company_id: string
          costing_method: string | null
          created_at: string
          created_by: string | null
          id: string
          item_id: string
          journal_entry_id: string | null
          lot_number: string | null
          notes: string | null
          qty: number
          qty_on_hand_after: number
          reference_doc_id: string | null
          reference_doc_type: string | null
          serial_number: string | null
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
          id?: string
          item_id: string
          journal_entry_id?: string | null
          lot_number?: string | null
          notes?: string | null
          qty: number
          qty_on_hand_after: number
          reference_doc_id?: string | null
          reference_doc_type?: string | null
          serial_number?: string | null
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
          id?: string
          item_id?: string
          journal_entry_id?: string | null
          lot_number?: string | null
          notes?: string | null
          qty?: number
          qty_on_hand_after?: number
          reference_doc_id?: string | null
          reference_doc_type?: string | null
          serial_number?: string | null
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
            foreignKeyName: "inventory_transactions_warehouse_id_fkey"
            columns: ["warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
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
      items: {
        Row: {
          barcode: string | null
          category_id: string
          cogs_account_id: string | null
          company_id: string
          costing_method: string | null
          created_at: string | null
          created_by: string | null
          default_ewt_code_id: string | null
          default_purchase_vat_id: string | null
          default_sales_vat_id: string | null
          description: string
          description_long: string | null
          id: string
          inventory_account_id: string | null
          is_active: boolean | null
          item_code: string
          item_type: string
          min_stock_level: number | null
          price_is_vat_inclusive: boolean
          purchase_expense_account_id: string | null
          reorder_point: number | null
          sales_account_id: string | null
          standard_cost: number
          standard_selling_price: number
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
          default_ewt_code_id?: string | null
          default_purchase_vat_id?: string | null
          default_sales_vat_id?: string | null
          description: string
          description_long?: string | null
          id?: string
          inventory_account_id?: string | null
          is_active?: boolean | null
          item_code: string
          item_type: string
          min_stock_level?: number | null
          price_is_vat_inclusive?: boolean
          purchase_expense_account_id?: string | null
          reorder_point?: number | null
          sales_account_id?: string | null
          standard_cost?: number
          standard_selling_price?: number
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
          default_ewt_code_id?: string | null
          default_purchase_vat_id?: string | null
          default_sales_vat_id?: string | null
          description?: string
          description_long?: string | null
          id?: string
          inventory_account_id?: string | null
          is_active?: boolean | null
          item_code?: string
          item_type?: string
          min_stock_level?: number | null
          price_is_vat_inclusive?: boolean
          purchase_expense_account_id?: string | null
          reorder_point?: number | null
          sales_account_id?: string | null
          standard_cost?: number
          standard_selling_price?: number
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
            foreignKeyName: "items_default_ewt_code_id_fkey"
            columns: ["default_ewt_code_id"]
            isOneToOne: false
            referencedRelation: "ewt_codes"
            referencedColumns: ["id"]
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
          fiscal_period_id: string | null
          id: string
          is_auto_reversal: boolean
          je_date: string
          je_number: string
          reference_doc_id: string | null
          reference_doc_type: string | null
          reversed_by_je_id: string | null
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
          fiscal_period_id?: string | null
          id?: string
          is_auto_reversal?: boolean
          je_date: string
          je_number: string
          reference_doc_id?: string | null
          reference_doc_type?: string | null
          reversed_by_je_id?: string | null
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
          fiscal_period_id?: string | null
          id?: string
          is_auto_reversal?: boolean
          je_date?: string
          je_number?: string
          reference_doc_id?: string | null
          reference_doc_type?: string | null
          reversed_by_je_id?: string | null
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
          id: string
          je_id: string
          line_number: number
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
          id?: string
          je_id: string
          line_number: number
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
          id?: string
          je_id?: string
          line_number?: number
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
            foreignKeyName: "journal_entry_lines_je_id_fkey"
            columns: ["je_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
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
            foreignKeyName: "number_series_document_type_id_fkey"
            columns: ["document_type_id"]
            isOneToOne: false
            referencedRelation: "ref_document_types"
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
          payment_mode_id: string | null
          posted_at: string | null
          posted_by: string | null
          reference_number: string | null
          released_by: string | null
          remarks: string | null
          status: string
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
          payment_mode_id?: string | null
          posted_at?: string | null
          posted_by?: string | null
          reference_number?: string | null
          released_by?: string | null
          remarks?: string | null
          status?: string
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
          payment_mode_id?: string | null
          posted_at?: string | null
          posted_by?: string | null
          reference_number?: string | null
          released_by?: string | null
          remarks?: string | null
          status?: string
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
          description: string
          form_type: string
          id: string
          is_active: boolean | null
          pt_code: string
          rate: number
          tax_code_id: string
          updated_at: string | null
          updated_by: string | null
        }
        Insert: {
          atc_id: string
          company_id: string
          created_at?: string | null
          created_by?: string | null
          description: string
          form_type?: string
          id?: string
          is_active?: boolean | null
          pt_code: string
          rate: number
          tax_code_id: string
          updated_at?: string | null
          updated_by?: string | null
        }
        Update: {
          atc_id?: string
          company_id?: string
          created_at?: string | null
          created_by?: string | null
          description?: string
          form_type?: string
          id?: string
          is_active?: boolean | null
          pt_code?: string
          rate?: number
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
          created_at: string
          created_by: string | null
          currency_code: string
          delivery_address: string | null
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
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          branch_id?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          currency_code?: string
          delivery_address?: string | null
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
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          branch_id?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          currency_code?: string
          delivery_address?: string | null
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
        ]
      }
      purchase_return_lines: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          description: string
          id: string
          item_id: string | null
          line_number: number
          max_qty: number
          reason: string | null
          return_id: string
          return_qty: number
          rr_line_id: string | null
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
          max_qty?: number
          reason?: string | null
          return_id: string
          return_qty?: number
          rr_line_id?: string | null
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
          max_qty?: number
          reason?: string | null
          return_id?: string
          return_qty?: number
          rr_line_id?: string | null
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
          cwt_tax_base: number | null
          cwt_variance_reason: string | null
          forex_adjustment: number
          id: string
          invoice_id: string
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
          cwt_tax_base?: number | null
          cwt_variance_reason?: string | null
          forex_adjustment?: number
          id?: string
          invoice_id: string
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
          cwt_tax_base?: number | null
          cwt_variance_reason?: string | null
          forex_adjustment?: number
          id?: string
          invoice_id?: string
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
          item_id: string | null
          line_number: number
          ordered_qty: number
          po_line_id: string | null
          received_qty: number
          reject_qty: number
          rr_id: string
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
          ordered_qty?: number
          po_line_id?: string | null
          received_qty?: number
          reject_qty?: number
          rr_id: string
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
          ordered_qty?: number
          po_line_id?: string | null
          received_qty?: number
          reject_qty?: number
          rr_id?: string
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
            foreignKeyName: "receiving_report_lines_rr_id_fkey"
            columns: ["rr_id"]
            isOneToOne: false
            referencedRelation: "receiving_reports"
            referencedColumns: ["id"]
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
          created_at: string
          created_by: string | null
          id: string
          po_id: string
          remarks: string | null
          rr_date: string
          rr_number: string
          status: string
          supplier_dr_no: string | null
          supplier_id: string
          supplier_name_snapshot: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          branch_id?: string | null
          company_id: string
          confirmed_at?: string | null
          confirmed_by?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          po_id: string
          remarks?: string | null
          rr_date: string
          rr_number: string
          status?: string
          supplier_dr_no?: string | null
          supplier_id: string
          supplier_name_snapshot: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          branch_id?: string | null
          company_id?: string
          confirmed_at?: string | null
          confirmed_by?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          po_id?: string
          remarks?: string | null
          rr_date?: string
          rr_number?: string
          status?: string
          supplier_dr_no?: string | null
          supplier_id?: string
          supplier_name_snapshot?: string
          updated_at?: string
          updated_by?: string | null
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
        ]
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
          company_id: string
          created_at: string
          created_by: string | null
          description: string
          discount_amount: number
          discount_percent: number
          id: string
          item_id: string | null
          line_number: number
          net_amount: number
          quantity: number
          revenue_account_id: string | null
          sales_invoice_id: string
          total_amount: number
          unit_price: number
          uom_id: string | null
          updated_at: string
          updated_by: string | null
          vat_amount: number
          vat_code_id: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          description: string
          discount_amount?: number
          discount_percent?: number
          id?: string
          item_id?: string | null
          line_number: number
          net_amount?: number
          quantity?: number
          revenue_account_id?: string | null
          sales_invoice_id: string
          total_amount?: number
          unit_price?: number
          uom_id?: string | null
          updated_at?: string
          updated_by?: string | null
          vat_amount?: number
          vat_code_id?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          description?: string
          discount_amount?: number
          discount_percent?: number
          id?: string
          item_id?: string | null
          line_number?: number
          net_amount?: number
          quantity?: number
          revenue_account_id?: string | null
          sales_invoice_id?: string
          total_amount?: number
          unit_price?: number
          uom_id?: string | null
          updated_at?: string
          updated_by?: string | null
          vat_amount?: number
          vat_code_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sales_invoice_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
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
        ]
      }
      sales_invoices: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          branch_id: string
          company_id: string
          created_at: string
          created_by: string | null
          currency_code: string
          customer_address_snapshot: string
          customer_id: string
          customer_name_snapshot: string
          customer_tin_snapshot: string
          cwt_amount_expected: number | null
          date: string
          due_date: string | null
          fiscal_period_id: string | null
          id: string
          is_cash_sale: boolean
          journal_entry_id: string | null
          memo: string | null
          payment_terms_id: string | null
          posted_at: string | null
          posted_by: string | null
          reference: string | null
          si_number: string
          status: string
          total_amount: number
          total_exempt_amount: number
          total_taxable_amount: number
          total_vat_amount: number
          total_zero_rated_amount: number
          updated_at: string
          updated_by: string | null
          void_reason_id: string | null
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          branch_id: string
          company_id: string
          created_at?: string
          created_by?: string | null
          currency_code?: string
          customer_address_snapshot?: string
          customer_id: string
          customer_name_snapshot?: string
          customer_tin_snapshot?: string
          cwt_amount_expected?: number | null
          date?: string
          due_date?: string | null
          fiscal_period_id?: string | null
          id?: string
          is_cash_sale?: boolean
          journal_entry_id?: string | null
          memo?: string | null
          payment_terms_id?: string | null
          posted_at?: string | null
          posted_by?: string | null
          reference?: string | null
          si_number: string
          status?: string
          total_amount?: number
          total_exempt_amount?: number
          total_taxable_amount?: number
          total_vat_amount?: number
          total_zero_rated_amount?: number
          updated_at?: string
          updated_by?: string | null
          void_reason_id?: string | null
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          branch_id?: string
          company_id?: string
          created_at?: string
          created_by?: string | null
          currency_code?: string
          customer_address_snapshot?: string
          customer_id?: string
          customer_name_snapshot?: string
          customer_tin_snapshot?: string
          cwt_amount_expected?: number | null
          date?: string
          due_date?: string | null
          fiscal_period_id?: string | null
          id?: string
          is_cash_sale?: boolean
          journal_entry_id?: string | null
          memo?: string | null
          payment_terms_id?: string | null
          posted_at?: string | null
          posted_by?: string | null
          reference?: string | null
          si_number?: string
          status?: string
          total_amount?: number
          total_exempt_amount?: number
          total_taxable_amount?: number
          total_vat_amount?: number
          total_zero_rated_amount?: number
          updated_at?: string
          updated_by?: string | null
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
            foreignKeyName: "sales_invoices_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
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
            foreignKeyName: "sales_invoices_payment_terms_id_fkey"
            columns: ["payment_terms_id"]
            isOneToOne: false
            referencedRelation: "payment_terms"
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
            foreignKeyName: "stock_adjustment_lines_gl_offset_account_id_fkey"
            columns: ["gl_offset_account_id"]
            isOneToOne: false
            referencedRelation: "chart_of_accounts"
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
      stock_transfer_lines: {
        Row: {
          company_id: string
          id: string
          item_id: string
          lot_number: string | null
          qty_transferred: number
          serial_number: string | null
          total_cost: number
          transfer_id: string
          unit_cost: number
        }
        Insert: {
          company_id: string
          id?: string
          item_id: string
          lot_number?: string | null
          qty_transferred: number
          serial_number?: string | null
          total_cost?: number
          transfer_id: string
          unit_cost?: number
        }
        Update: {
          company_id?: string
          id?: string
          item_id?: string
          lot_number?: string | null
          qty_transferred?: number
          serial_number?: string | null
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
            foreignKeyName: "stock_transfer_lines_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
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
            foreignKeyName: "supplier_debit_memos_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
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
          default_ewt_code_id: string | null
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
          default_ewt_code_id?: string | null
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
          default_ewt_code_id?: string | null
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
            foreignKeyName: "suppliers_default_ewt_code_id_fkey"
            columns: ["default_ewt_code_id"]
            isOneToOne: false
            referencedRelation: "ewt_codes"
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
            foreignKeyName: "sys_feature_enablement_feature_definition_id_fkey"
            columns: ["feature_definition_id"]
            isOneToOne: false
            referencedRelation: "ref_feature_definitions"
            referencedColumns: ["id"]
          },
        ]
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
          description: string
          gl_account_id: string | null
          id: string
          is_active: boolean | null
          rate: number
          tax_type: string
          updated_at: string | null
          updated_by: string | null
        }
        Insert: {
          code: string
          created_at?: string | null
          created_by?: string | null
          description: string
          gl_account_id?: string | null
          id?: string
          is_active?: boolean | null
          rate: number
          tax_type: string
          updated_at?: string | null
          updated_by?: string | null
        }
        Update: {
          code?: string
          created_at?: string | null
          created_by?: string | null
          description?: string
          gl_account_id?: string | null
          id?: string
          is_active?: boolean | null
          rate?: number
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
        ]
      }
      vat_codes: {
        Row: {
          created_at: string | null
          description: string
          id: string
          is_active: boolean | null
          relief_category: string | null
          tax_code_id: string
          transaction_type: string
          vat_classification: string
          vat_code: string
        }
        Insert: {
          created_at?: string | null
          description: string
          id?: string
          is_active?: boolean | null
          relief_category?: string | null
          tax_code_id: string
          transaction_type: string
          vat_classification: string
          vat_code: string
        }
        Update: {
          created_at?: string | null
          description?: string
          id?: string
          is_active?: boolean | null
          relief_category?: string | null
          tax_code_id?: string
          transaction_type?: string
          vat_classification?: string
          vat_code?: string
        }
        Relationships: [
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
          created_at: string
          created_by: string | null
          currency_code: string
          due_date: string | null
          ewt_amount_expected: number | null
          fiscal_period_id: string | null
          id: string
          journal_entry_id: string | null
          memo: string | null
          payment_terms_id: string | null
          posted_at: string | null
          posted_by: string | null
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
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          bill_date: string
          bill_number: string
          branch_id?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          currency_code?: string
          due_date?: string | null
          ewt_amount_expected?: number | null
          fiscal_period_id?: string | null
          id?: string
          journal_entry_id?: string | null
          memo?: string | null
          payment_terms_id?: string | null
          posted_at?: string | null
          posted_by?: string | null
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
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          bill_date?: string
          bill_number?: string
          branch_id?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          currency_code?: string
          due_date?: string | null
          ewt_amount_expected?: number | null
          fiscal_period_id?: string | null
          id?: string
          journal_entry_id?: string | null
          memo?: string | null
          payment_terms_id?: string | null
          posted_at?: string | null
          posted_by?: string | null
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
            foreignKeyName: "vendor_bills_fiscal_period_id_fkey"
            columns: ["fiscal_period_id"]
            isOneToOne: false
            referencedRelation: "fiscal_periods"
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
            foreignKeyName: "vendor_bills_payment_terms_id_fkey"
            columns: ["payment_terms_id"]
            isOneToOne: false
            referencedRelation: "payment_terms"
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
            foreignKeyName: "vendor_bills_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
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
        ]
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
          fiscal_period_id: string | null
          is_auto_reversal: boolean | null
          je_date: string | null
          je_description: string | null
          je_id: string | null
          je_number: string | null
          je_status: string | null
          line_description: string | null
          line_id: string | null
          line_number: number | null
          normal_balance: string | null
          period_end: string | null
          period_name: string | null
          period_start: string | null
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
            foreignKeyName: "journal_entry_lines_je_id_fkey"
            columns: ["je_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
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
        ]
      }
      vw_sales_invoice_register: {
        Row: {
          branch_id: string | null
          company_id: string | null
          customer_name_snapshot: string | null
          customer_tin_snapshot: string | null
          date: string | null
          invoice_id: string | null
          memo: string | null
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
          invoice_id?: string | null
          memo?: string | null
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
          invoice_id?: string | null
          memo?: string | null
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
        ]
      }
    }
    Functions: {
      can_admin_company: { Args: { p_company_id: string }; Returns: boolean }
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
      fn_add_posting_line: {
        Args: {
          p_account_id: string
          p_branch_id?: string
          p_cost_center_id?: string
          p_credit?: number
          p_debit?: number
          p_department_id?: string
          p_description: string
          p_je_id: string
          p_line_number: number
        }
        Returns: string
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
      fn_assert_posting_source: {
        Args: {
          p_company_id: string
          p_document_type: string
          p_source_id: string
        }
        Returns: Json
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
      fn_atc_code_is_current: {
        Args: {
          p_as_of_date?: string
          p_atc_id: string
          p_tax_category: string
        }
        Returns: boolean
      }
      fn_atc_code_used: { Args: { p_atc_id: string }; Returns: boolean }
      fn_begin_source_posting: {
        Args: {
          p_document_type: string
          p_done_statuses?: string[]
          p_ready_statuses?: string[]
          p_source_id: string
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
      fn_can_perform: {
        Args: {
          p_action: string
          p_company_id: string
          p_document_type?: string
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
      fn_complete_purchase_return: {
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
      fn_compute_ewt_return: {
        Args: { p_company_id: string; p_quarter: number; p_year: number }
        Returns: {
          total_ewt_withheld: number
          total_tax_base: number
        }[]
      }
      fn_confirm_receiving_report: {
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
      fn_create_posted_journal_entry: {
        Args: {
          p_branch_id: string
          p_company_id: string
          p_description: string
          p_je_date: string
          p_je_number: string
          p_reference_doc_id: string
          p_reference_doc_type: string
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
      fn_finalize_journal_entry: {
        Args: { p_je_id: string }
        Returns: undefined
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
      fn_generate_form_2307_issued: {
        Args: {
          p_company_id: string
          p_tax_quarter: number
          p_tax_year: number
        }
        Returns: Json
      }
      fn_generate_tax_calendar: {
        Args: { p_company_id: string; p_fiscal_year: number }
        Returns: undefined
      }
      fn_get_accounting_trace: {
        Args: {
          p_journal_entry_id?: string
          p_source_doc_id?: string
          p_source_doc_type?: string
        }
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
      fn_gl_impact_payload: {
        Args: { p_je_id: string; p_mode?: string; p_rule_explanation?: string }
        Returns: Json
      }
      fn_mark_tax_event_filed: {
        Args: { p_date_filed: string; p_efps_ref?: string; p_event_id: string }
        Returns: undefined
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
          p_je_date: string
          p_lines: Json
          p_reference_doc_type: string
        }
        Returns: string
      }
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
      fn_preview_gl_impact: {
        Args: {
          p_posting_date?: string
          p_source_doc_id: string
          p_source_doc_type: string
        }
        Returns: Json
      }
      fn_rebuild_document_vat_details: {
        Args: { p_source_doc_id: string; p_source_doc_type: string }
        Returns: undefined
      }
      fn_receive_inventory: { Args: { p_data: Json }; Returns: string }
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
      fn_register_fixed_asset: { Args: { p_data: Json }; Returns: string }
      fn_report_snapshot_key_uuid: { Args: { p_key: string }; Returns: string }
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
      fn_resolve_posting_source: {
        Args: { p_document_type: string; p_lock?: boolean; p_source_id: string }
        Returns: Json
      }
      fn_reverse_je: {
        Args: { p_je_id: string; p_reversal_date?: string }
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
      fn_row_written_by_current_txn: {
        Args: { p_xmin_raw: number }
        Returns: boolean
      }
      fn_save_cash_purchase: {
        Args: { p_cp_id: string; p_header: Json; p_lines: Json }
        Returns: string
      }
      fn_save_cash_sale: {
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
      fn_save_debit_memo: {
        Args: {
          p_dm_id: string
          p_header: Json
          p_lines: Json
          p_next_status?: string
        }
        Returns: string
      }
      fn_save_payment_voucher: {
        Args: { p_header: Json; p_lines: Json; p_voucher_id: string }
        Returns: string
      }
      fn_save_purchase_order: {
        Args: { p_header: Json; p_lines: Json; p_po_id: string }
        Returns: string
      }
      fn_save_purchase_return: {
        Args: { p_header: Json; p_lines: Json; p_return_id: string }
        Returns: string
      }
      fn_save_receipt: {
        Args: { p_header: Json; p_lines: Json; p_receipt_id: string }
        Returns: string
      }
      fn_save_receiving_report: {
        Args: { p_header: Json; p_lines: Json; p_rr_id: string }
        Returns: string
      }
      fn_save_sales_invoice: {
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
      fn_save_vendor_credit: {
        Args: { p_header: Json; p_lines: Json; p_vc_id: string }
        Returns: string
      }
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
      fn_snapshot_wht_export: {
        Args: {
          p_company_id: string
          p_quarter: number
          p_report_type: string
          p_year: number
        }
        Returns: string
      }
      fn_supersede_form_2307_issued: {
        Args: { p_issuance_id: string; p_reason?: string }
        Returns: string
      }
      fn_transfer_fixed_asset: { Args: { p_data: Json }; Returns: string }
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
      fn_validate_company_vat_amount: {
        Args: { p_company_id: string; p_context?: string; p_vat_amount: number }
        Returns: undefined
      }
      fn_validate_company_vat_code: {
        Args: {
          p_company_id: string
          p_context?: string
          p_transaction_type: string
          p_vat_code_id: string
        }
        Returns: undefined
      }
      fn_validate_document_vat_registration: {
        Args: {
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
      fn_validate_invoice_posting_totals: {
        Args: { p_document_type: string; p_source_id: string }
        Returns: undefined
      }
      fn_validate_payment_voucher_ewt_ready: {
        Args: { p_voucher_id: string }
        Returns: undefined
      }
      fn_validate_payment_voucher_line_ewt:
        | {
            Args: {
              p_atc_code_id: string
              p_company_id: string
              p_ewt_amount: number
              p_payment_amount: number
            }
            Returns: undefined
          }
        | {
            Args: {
              p_atc_code_id: string
              p_company_id: string
              p_ewt_amount: number
              p_ewt_tax_base?: number
              p_ewt_variance_reason?: string
              p_payment_amount: number
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
          p_cwt_tax_base?: number
          p_cwt_variance_reason?: string
          p_payment_amount: number
        }
        Returns: undefined
      }
      fn_validate_sales_invoice_accounting_ready: {
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
      fn_void_sales_invoice: {
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
      is_any_company_admin: { Args: never; Returns: boolean }
      is_company_member: { Args: { p_company_id: string }; Returns: boolean }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
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

