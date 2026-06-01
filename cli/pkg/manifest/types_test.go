package manifest

import "testing"

func TestNamespace(t *testing.T) {
	cases := []struct {
		env  string
		want string
	}{
		{"dev", "dev"},
		{"stage", "stage"},
		{"prod", "prod"},
		{"", "default"},
	}
	for _, tc := range cases {
		m := &Manifest{Environment: tc.env}
		if got := m.Namespace(); got != tc.want {
			t.Errorf("Namespace(%q) = %q, want %q", tc.env, got, tc.want)
		}
	}
}

func TestNeedsGCPServiceAccount(t *testing.T) {
	cases := []struct {
		roles []string
		want  bool
	}{
		{nil, false},
		{[]string{}, false},
		{[]string{"roles/secretmanager.secretAccessor"}, true},
		{[]string{"roles/secretmanager.secretAccessor", "roles/storage.objectViewer"}, true},
	}
	for _, tc := range cases {
		m := &Manifest{IAM: IAMConfig{Roles: tc.roles}}
		if got := m.NeedsGCPServiceAccount(); got != tc.want {
			t.Errorf("NeedsGCPServiceAccount(%v) = %v, want %v", tc.roles, got, tc.want)
		}
	}
}

func TestServiceType(t *testing.T) {
	cases := []struct {
		svcType string
		want    string
	}{
		{"public", "LoadBalancer"},
		{"private", "ClusterIP"},
		{"", "ClusterIP"},
	}
	for _, tc := range cases {
		m := &Manifest{Service: Service{Type: tc.svcType}}
		if got := m.ServiceType(); got != tc.want {
			t.Errorf("ServiceType(%q) = %q, want %q", tc.svcType, got, tc.want)
		}
	}
}

func TestGCPServiceAccountName(t *testing.T) {
	m := &Manifest{Name: "api-service"}
	got := m.GCPServiceAccountName("my-project")
	want := "api-service@my-project.iam.gserviceaccount.com"
	if got != want {
		t.Errorf("GCPServiceAccountName = %q, want %q", got, want)
	}
}
