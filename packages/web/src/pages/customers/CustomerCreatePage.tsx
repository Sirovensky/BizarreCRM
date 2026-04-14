import { useState, useEffect, useRef, useCallback } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Loader2, Save, X, AlertTriangle } from 'lucide-react';
import toast from 'react-hot-toast';
import { customerApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { formatPhoneAsYouType, stripPhone } from '@/utils/phoneFormat';
import { BackButton } from '@/components/shared/BackButton';
import type { CreateCustomerInput } from '@bizarre-crm/shared';

interface FormState {
  first_name: string;
  last_name: string;
  type: 'individual' | 'business';
  organization: string;
  email: string;
  phone: string;
  mobile: string;
  address1: string;
  address2: string;
  city: string;
  state: string;
  postcode: string;
  country: string;
  referred_by: string;
  comments: string;
  tags: string;
  email_opt_in: boolean;
  sms_opt_in: boolean;
}

const initialForm: FormState = {
  first_name: '',
  last_name: '',
  type: 'individual',
  organization: '',
  email: '',
  phone: '',
  mobile: '',
  address1: '',
  address2: '',
  city: '',
  state: '',
  postcode: '',
  country: 'US',
  referred_by: '',
  comments: '',
  tags: '',
  email_opt_in: true,
  sms_opt_in: true,
};

export function CustomerCreatePage() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const queryClient = useQueryClient();
  const [form, setForm] = useState<FormState>(initialForm);
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [duplicates, setDuplicates] = useState<any[]>([]);
  const dupTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const didPrefillPhoneRef = useRef(false);
  const phoneParam = searchParams.get('phone') || '';

  const checkDuplicates = useCallback((keyword: string) => {
    if (dupTimerRef.current) clearTimeout(dupTimerRef.current);
    if (!keyword || keyword.length < 3) { setDuplicates([]); return; }
    dupTimerRef.current = setTimeout(async () => {
      try {
        const res = await customerApi.list({ page: 1, pagesize: 5, keyword });
        const matches = res.data?.data?.customers || [];
        setDuplicates(matches);
      } catch (err: unknown) {
        setDuplicates([]);
      }
    }, 400);
  }, []);

  const handleFieldBlur = useCallback((field: 'name' | 'phone' | 'email') => {
    if (field === 'name') {
      const name = `${form.first_name} ${form.last_name}`.trim();
      checkDuplicates(name);
    } else if (field === 'phone') {
      const phone = form.phone || form.mobile;
      checkDuplicates(phone);
    } else if (field === 'email') {
      checkDuplicates(form.email);
    }
  }, [form.first_name, form.last_name, form.phone, form.mobile, form.email, checkDuplicates]);

  useEffect(() => {
    if (didPrefillPhoneRef.current) return;
    const digits = stripPhone(phoneParam);
    if (digits.length < 7) return;

    didPrefillPhoneRef.current = true;
    const formattedPhone = formatPhoneAsYouType(digits);
    setForm((prev) => (
      prev.phone || prev.mobile
        ? prev
        : { ...prev, phone: formattedPhone }
    ));
    checkDuplicates(digits);
  }, [phoneParam, checkDuplicates]);

  const createMutation = useMutation({
    mutationFn: (data: CreateCustomerInput) => customerApi.create(data),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['customers'] });
      toast.success('Customer created');
      const customer = res.data?.data;
      navigate(`/customers/${customer?.id}`);
    },
    onError: () => toast.error('Failed to create customer'),
  });

  const updateField = <K extends keyof FormState>(
    key: K,
    value: FormState[K],
  ) => {
    setForm((prev) => ({ ...prev, [key]: value }));
    if (errors[key]) {
      setErrors((prev) => {
        const next = { ...prev };
        delete next[key];
        return next;
      });
    }
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();

    // Validate
    const newErrors: Record<string, string> = {};
    if (!form.first_name.trim()) {
      newErrors.first_name = 'First name is required';
    }
    if (Object.keys(newErrors).length > 0) {
      setErrors(newErrors);
      return;
    }

    const payload: CreateCustomerInput = {
      first_name: form.first_name.trim(),
      last_name: form.last_name.trim() || undefined,
      type: form.type,
      organization: form.organization.trim() || undefined,
      email: form.email.trim() || undefined,
      phone: stripPhone(form.phone) || undefined,
      mobile: stripPhone(form.mobile) || undefined,
      address1: form.address1.trim() || undefined,
      address2: form.address2.trim() || undefined,
      city: form.city.trim() || undefined,
      state: form.state.trim() || undefined,
      postcode: form.postcode.trim() || undefined,
      country: form.country.trim() || undefined,
      referred_by: form.referred_by.trim() || undefined,
      comments: form.comments.trim() || undefined,
      tags: form.tags
        .split(',')
        .map((t) => t.trim())
        .filter(Boolean),
      email_opt_in: form.email_opt_in,
      sms_opt_in: form.sms_opt_in,
    };

    createMutation.mutate(payload);
  };

  return (
    <div className="max-w-2xl mx-auto">
      {/* Header */}
      <div className="mb-6 flex items-center gap-4">
        <BackButton />
        <div>
          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">
            New Customer
          </h1>
          <p className="text-surface-500 dark:text-surface-400">
            Add a new customer to the system
          </p>
        </div>
      </div>

      <form onSubmit={handleSubmit}>
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Basic Info */}
          <div className="card p-4 md:p-6">
            <h2 className="text-base font-semibold text-surface-900 dark:text-surface-100 mb-4">
              Basic Information
            </h2>
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <FormField
                  label="First Name"
                  htmlFor="first_name"
                  required
                  error={errors.first_name}
                >
                  <input
                    id="first_name"
                    type="text"
                    value={form.first_name}
                    onChange={(e) => updateField('first_name', e.target.value)}
                    onBlur={() => handleFieldBlur('name')}
                    className={cn('input', errors.first_name && 'border-red-500 dark:border-red-500')}
                    placeholder="John"
                  />
                </FormField>
                <FormField label="Last Name" htmlFor="last_name">
                  <input
                    id="last_name"
                    type="text"
                    value={form.last_name}
                    onChange={(e) => updateField('last_name', e.target.value)}
                    onBlur={() => handleFieldBlur('name')}
                    className="input"
                    placeholder="Doe"
                  />
                </FormField>
              </div>
              <FormField label="Type">
                <select
                  value={form.type}
                  onChange={(e) =>
                    updateField('type', e.target.value as 'individual' | 'business')
                  }
                  className="input"
                >
                  <option value="individual">Individual</option>
                  <option value="business">Business</option>
                </select>
              </FormField>
              <FormField label="Organization">
                <input
                  type="text"
                  value={form.organization}
                  onChange={(e) => updateField('organization', e.target.value)}
                  className="input"
                  placeholder="Acme Corp"
                />
              </FormField>
            </div>
          </div>

          {/* Contact */}
          <div className="card p-4 md:p-6">
            <h2 className="text-base font-semibold text-surface-900 dark:text-surface-100 mb-4">
              Contact Information
            </h2>
            <div className="space-y-4">
              <FormField label="Email" htmlFor="email">
                <input
                  id="email"
                  type="email"
                  value={form.email}
                  onChange={(e) => updateField('email', e.target.value)}
                  onBlur={() => handleFieldBlur('email')}
                  className="input"
                  placeholder="john@example.com"
                />
              </FormField>
              <FormField label="Phone" htmlFor="phone">
                <input
                  id="phone"
                  type="tel"
                  value={form.phone}
                  onChange={(e) => updateField('phone', formatPhoneAsYouType(e.target.value))}
                  onBlur={() => handleFieldBlur('phone')}
                  className="input"
                  placeholder="(303) 555-1234"
                />
              </FormField>
              <FormField label="Mobile" htmlFor="mobile">
                <input
                  id="mobile"
                  type="tel"
                  value={form.mobile}
                  onChange={(e) => updateField('mobile', formatPhoneAsYouType(e.target.value))}
                  onBlur={() => handleFieldBlur('phone')}
                  className="input"
                  placeholder="(303) 555-1234"
                />
              </FormField>
            </div>
          </div>

          {/* Possible Duplicates */}
          {duplicates.length > 0 && (
            <div className="col-span-full rounded-lg border border-amber-300 dark:border-amber-700 bg-amber-50 dark:bg-amber-900/20 p-4">
              <div className="flex items-center gap-2 mb-2">
                <AlertTriangle className="h-4 w-4 text-amber-600 dark:text-amber-400" />
                <h3 className="text-sm font-semibold text-amber-800 dark:text-amber-300">Possible matches found</h3>
              </div>
              <div className="space-y-1.5">
                {duplicates.map((c: any) => (
                  <Link key={c.id} to={`/customers/${c.id}`}
                    className="flex items-center justify-between rounded-md px-3 py-2 text-sm bg-white dark:bg-surface-800 border border-surface-200 dark:border-surface-700 hover:bg-surface-50 dark:hover:bg-surface-700 transition-colors">
                    <span className="font-medium text-surface-900 dark:text-surface-100">
                      {c.first_name} {c.last_name}
                    </span>
                    <span className="text-surface-500 dark:text-surface-400 text-xs">
                      {c.mobile || c.phone || c.email || ''}
                    </span>
                  </Link>
                ))}
              </div>
              <button onClick={() => setDuplicates([])} className="mt-2 text-xs text-amber-600 dark:text-amber-400 hover:underline">
                Dismiss
              </button>
            </div>
          )}

          {/* Address */}
          <div className="card p-4 md:p-6">
            <h2 className="text-base font-semibold text-surface-900 dark:text-surface-100 mb-4">
              Address
            </h2>
            <div className="space-y-4">
              <FormField label="Address Line 1">
                <input
                  type="text"
                  value={form.address1}
                  onChange={(e) => updateField('address1', e.target.value)}
                  className="input"
                  placeholder="123 Main St"
                />
              </FormField>
              <FormField label="Address Line 2">
                <input
                  type="text"
                  value={form.address2}
                  onChange={(e) => updateField('address2', e.target.value)}
                  className="input"
                  placeholder="Suite 100"
                />
              </FormField>
              <div className="grid grid-cols-2 gap-4">
                <FormField label="City">
                  <input
                    type="text"
                    value={form.city}
                    onChange={(e) => updateField('city', e.target.value)}
                    className="input"
                    placeholder="Longmont"
                  />
                </FormField>
                <FormField label="State">
                  <input
                    type="text"
                    value={form.state}
                    onChange={(e) => updateField('state', e.target.value)}
                    className="input"
                    placeholder="CO"
                  />
                </FormField>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <FormField label="Postcode">
                  <input
                    type="text"
                    value={form.postcode}
                    onChange={(e) => updateField('postcode', e.target.value)}
                    className="input"
                    placeholder="80501"
                  />
                </FormField>
                <FormField label="Country">
                  <input
                    type="text"
                    value={form.country}
                    onChange={(e) => updateField('country', e.target.value)}
                    className="input"
                    placeholder="US"
                  />
                </FormField>
              </div>
            </div>
          </div>

          {/* Additional */}
          <div className="card p-4 md:p-6">
            <h2 className="text-base font-semibold text-surface-900 dark:text-surface-100 mb-4">
              Additional Information
            </h2>
            <div className="space-y-4">
              <FormField label="Referred By">
                <input
                  type="text"
                  value={form.referred_by}
                  onChange={(e) => updateField('referred_by', e.target.value)}
                  className="input"
                  placeholder="Google, Friend, etc."
                />
              </FormField>
              <FormField label="Tags">
                <input
                  type="text"
                  value={form.tags}
                  onChange={(e) => updateField('tags', e.target.value)}
                  className="input"
                  placeholder="vip, wholesale (comma separated)"
                />
              </FormField>
              <FormField label="Comments">
                <textarea
                  value={form.comments}
                  onChange={(e) => updateField('comments', e.target.value)}
                  className="input min-h-[80px] resize-y"
                  placeholder="Internal notes about this customer..."
                  rows={3}
                />
              </FormField>
              <div className="flex items-center gap-6 pt-2">
                <label className="flex items-center gap-2 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={form.email_opt_in}
                    onChange={(e) => updateField('email_opt_in', e.target.checked)}
                    className="h-4 w-4 rounded border-surface-300 dark:border-surface-600 text-primary-600 focus:ring-primary-500"
                  />
                  <span className="text-sm text-surface-700 dark:text-surface-300">
                    Email opt-in
                  </span>
                </label>
                <label className="flex items-center gap-2 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={form.sms_opt_in}
                    onChange={(e) => updateField('sms_opt_in', e.target.checked)}
                    className="h-4 w-4 rounded border-surface-300 dark:border-surface-600 text-primary-600 focus:ring-primary-500"
                  />
                  <span className="text-sm text-surface-700 dark:text-surface-300">
                    SMS opt-in
                  </span>
                </label>
              </div>
            </div>
          </div>
        </div>

        {/* Actions */}
        <div className="mt-6 flex items-center justify-end gap-3">
          <button
            type="button"
            onClick={() => navigate(-1)}
            className="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-surface-600 dark:text-surface-300 bg-white dark:bg-surface-800 border border-surface-200 dark:border-surface-700 rounded-lg hover:bg-surface-50 dark:hover:bg-surface-700 transition-colors"
          >
            <X className="h-4 w-4" />
            Cancel
          </button>
          <button
            type="submit"
            disabled={createMutation.isPending}
            className="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-primary-600 hover:bg-primary-700 rounded-lg transition-colors shadow-sm disabled:opacity-60 disabled:cursor-not-allowed"
          >
            {createMutation.isPending ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              <Save className="h-4 w-4" />
            )}
            {createMutation.isPending ? 'Creating...' : 'Create Customer'}
          </button>
        </div>
      </form>
    </div>
  );
}

function FormField({
  label,
  htmlFor,
  required,
  error,
  children,
}: {
  label: string;
  htmlFor?: string;
  required?: boolean;
  error?: string;
  children: React.ReactNode;
}) {
  return (
    <div>
      <label htmlFor={htmlFor} className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
        {label}
        {required && <span className="text-red-500 ml-0.5">*</span>}
      </label>
      {children}
      {error && (
        <p className="mt-1 text-xs text-red-500">{error}</p>
      )}
    </div>
  );
}
