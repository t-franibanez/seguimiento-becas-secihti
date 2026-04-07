using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;

namespace SECIHTI.Controllers
{
    [ApiController]
    [Route("[controller]")]
    [AllowAnonymous]
    public class HealthController : ControllerBase
    {
        private readonly IConfiguration _configuration;

        public HealthController(IConfiguration configuration)
        {
            _configuration = configuration;
        }

        [HttpGet]
        public IActionResult Get()
        {
            return Ok(new
            {
                status = "healthy",
                samlConfigured = !string.IsNullOrEmpty(_configuration["Saml2:Issuer"]),
                keyVaultConfigured = !string.IsNullOrEmpty(_configuration["keyVaultUri"]),
            });
        }
    }
}
