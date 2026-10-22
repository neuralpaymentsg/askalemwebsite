"use strict";
(function(){
  const form = document.getElementById("recovery-form");
  const message = document.getElementById("message");
  const submit = document.getElementById("submit");
  const mode = document.body.getAttribute("data-mode");
  let token = "";
  if(mode === "reset"){
    const params = new URLSearchParams(location.hash.slice(1));
    token = params.get("token") || "";
    history.replaceState(null, "", location.pathname);
    if(!/^[A-Za-z0-9_-]{40,100}$/.test(token)){
      show("This reset link is invalid. Request a new one.", false);
      submit.disabled = true;
    }
  }
  function show(text, success){
    message.textContent = text;
    message.className = "feedback " + (success ? "ok" : "err");
    message.setAttribute("role", "status");
  }
  form.addEventListener("submit", async function(event){
    event.preventDefault();
    submit.disabled = true;
    const original = submit.textContent;
    submit.textContent = "Please wait…";
    let endpoint, payload;
    if(mode === "forgot"){
      endpoint = "/api/auth/forgot-password";
      payload = {email: String(new FormData(form).get("email") || "").trim()};
    } else {
      const fd = new FormData(form);
      const password = String(fd.get("password") || "");
      const confirm = String(fd.get("confirm") || "");
      if(password.length < 12 || password.length > 256){
        show("Please use a password between 12 and 256 characters.", false);
        submit.disabled = false;
        submit.textContent = original;
        return;
      }
      if(password !== confirm){
        show("Passwords do not match.", false);
        submit.disabled = false;
        submit.textContent = original;
        return;
      }
      endpoint = "/api/auth/reset-password";
      payload = {token: token, password: password};
    }
    try{
      const res = await fetch(endpoint,{
        method:"POST",
        headers:{"Content-Type":"application/json"},
        credentials:"same-origin",
        cache:"no-store",
        body:JSON.stringify(payload)
      });
      const body = await res.json().catch(()=>({}));
      if(!res.ok){
        const detail = typeof body.detail === "string" ? body.detail : "Request failed. Please try again.";
        throw new Error(detail);
      }
      show(body.message || (mode === "forgot"
        ? "If the email is registered, a recovery link will be sent."
        : "Your password has been changed."), true);
      if(mode === "reset"){
        form.reset();
        form.style.display = "none";
        document.getElementById("login-return").hidden = false;
        token = "";
      }
    }catch(err){
      show(err.message || "Unable to complete the request.", false);
    }finally{
      submit.disabled = mode === "reset" && !token;
      submit.textContent = original;
    }
  });
})();
