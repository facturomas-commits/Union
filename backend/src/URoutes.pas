unit URoutes;

interface

procedure RegisterRoutes;

implementation

uses
  Horse,
  UAuth, UCatalogRoutes, UScheduleRoutes, UOpsRoutes, UFreightRoutes, UReportRoutes, UWeb;

procedure RegisterRoutes;
begin
  // Web (SPA)
  RegisterWebRoutes;

  // Autenticación
  THorse.Post('/api/auth/login', LoginHandler);
  THorse.Post('/api/auth/logout', LogoutHandler);
  THorse.Get('/api/auth/me', MeHandler);
  THorse.Post('/api/auth/change-password', ChangePasswordHandler);

  // Módulos
  RegisterCatalogRoutes;
  RegisterScheduleRoutes;
  RegisterOpsRoutes;
  RegisterFreightRoutes;
  RegisterReportRoutes;
end;

end.
